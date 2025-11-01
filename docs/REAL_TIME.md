# Real-Time Features

Listopia uses **[Hotwire](https://hotwired.dev/) - Turbo Streams + Stimulus** to deliver real-time collaborative experiences. The philosophy is simple: **prefer Turbo Streams for all real-time updates**, use Stimulus only when Turbo cannot solve the problem.

## Architecture

### Turbo Streams (Primary)

Turbo Streams send HTML updates over WebSocket connections, replacing or appending DOM elements in real-time. This is the primary mechanism for all real-time features.

```
Model Changes → Broadcast Job → Turbo Stream → Browser DOM Update
```

### Stimulus Controllers (Last Resort)

Stimulus handles client-side logic when Turbo Streams are insufficient. Examples: drag-and-drop with custom sorting, form field validation, animation triggers.

### Technology Stack

- **[Turbo Drive](https://turbo.hotwired.dev/handbook/drive)** - Fast page navigation
- **[Turbo Frames](https://turbo.hotwired.dev/handbook/frames)** - Scoped page sections  
- **[Turbo Streams](https://turbo.hotwired.dev/handbook/streams)** - Real-time HTML updates
- **[Action Cable](https://guides.rubyonrails.org/action_cable_overview.html)** - WebSocket server
- **[Stimulus](https://stimulus.hotwired.dev/)** - JavaScript controller framework

## Turbo Streams Implementation

### Broadcasting from Models

Models broadcast changes automatically via callbacks:

```ruby
# app/models/list_item.rb
class ListItem < ApplicationRecord
  belongs_to :list
  
  # Broadcast on create, update, destroy
  after_create_commit :broadcast_created
  after_update_commit :broadcast_updated
  after_destroy_commit :broadcast_destroyed

  private

  def broadcast_created
    broadcast_to_list_collaborators(:created)
  end

  def broadcast_updated
    broadcast_to_list_collaborators(:updated)
  end

  def broadcast_destroyed
    broadcast_to_list_collaborators(:destroyed)
  end

  def broadcast_to_list_collaborators(action)
    # Get all users viewing this list
    target_users = list.collaborators + [list.owner]
    
    target_users.each do |user|
      # Broadcast to each user's personal stream
      Turbo::StreamsChannel.broadcast_render_to(
        "list_#{list.id}_user_#{user.id}",
        template: "list_items/#{action}",
        locals: { item: self, list: list, user: user }
      )
    end
  end
end
```

### Stream Templates

Define what gets sent to the browser:

```erb
<!-- app/views/list_items/_created.turbo_stream.erb -->
<%= turbo_stream.append "list_items_#{list.id}" do %>
  <%= render "list_items/item", item: item, list: list %>
<% end %>

<%= turbo_stream.replace "list_progress_#{list.id}" do %>
  <%= render "lists/progress_bar", list: list %>
<% end %>
```

### Controller Integration

Make controllers respond with Turbo Streams:

```ruby
# app/controllers/list_items_controller.rb
class ListItemsController < ApplicationController
  def create
    @list = current_user.lists.find(params[:list_id])
    @item = @list.list_items.build(item_params)
    
    if @item.save
      # Automatically renders list_items/create.turbo_stream.erb
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @list }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @item = current_user.accessible_list_items.find(params[:id])
    
    if @item.update(item_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @item.list }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def toggle_completion
    @item = current_user.accessible_list_items.find(params[:id])
    @list = @item.list
    
    @item.update(
      status: @item.status_completed? ? :pending : :completed,
      completed_at: @item.status_completed? ? nil : Time.current
    )
    
    respond_to do |format|
      format.turbo_stream
      format.json { render json: { status: @item.status } }
    end
  end
end
```

### Optimistic UI Updates

For immediate user feedback, update the DOM before the server responds:

```erb
<!-- app/views/list_items/item.html.erb -->
<div id="list_item_<%= item.id %>" data-item-id="<%= item.id %>">
  <input 
    type="checkbox" 
    <%= "checked" if item.status_completed? %>
    data-action="change->list-items#toggleCompletion"
  />
  <span><%= item.title %></span>
</div>
```

```javascript
// app/javascript/controllers/list_items_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  toggleCompletion(event) {
    const checkbox = event.target
    const itemId = checkbox.dataset.itemId
    const itemDiv = this.element.closest(`#list_item_${itemId}`)
    
    // Optimistic update: show change immediately
    checkbox.checked ? 
      itemDiv.classList.add('completed') : 
      itemDiv.classList.remove('completed')
    
    // Send to server (Turbo Stream response updates correctly)
    fetch(`/list_items/${itemId}/toggle_completion`, {
      method: 'PATCH',
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        'Accept': 'text/vnd.turbo-stream.html'
      }
    })
    .catch(error => {
      // Revert on error
      checkbox.checked = !checkbox.checked
      checkbox.checked ? 
        itemDiv.classList.add('completed') : 
        itemDiv.classList.remove('completed')
    })
  }
}
```

## Stimulus Controllers

Use Stimulus **only** when Turbo cannot solve the problem. Examples:

### 1. Drag-and-Drop Reordering

Turbo can't handle complex drag interactions, so Stimulus is appropriate:

```javascript
// app/javascript/controllers/sortable_controller.js
import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static values = { url: String }

  connect() {
    this.sortable = Sortable.create(this.element, {
      handle: '.drag-handle',
      animation: 150,
      onEnd: this.handleReorder.bind(this)
    })
  }

  async handleReorder(event) {
    const itemId = event.item.dataset.itemId
    const position = event.newIndex
    
    const response = await fetch(this.urlValue, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        'Accept': 'text/vnd.turbo-stream.html'
      },
      body: JSON.stringify({ item_id: itemId, position: position })
    })
    
    Turbo.renderStreamMessage(await response.text())
  }
}
```

### 2. Form Validation

Real-time feedback on form fields:

```javascript
// app/javascript/controllers/form_validation_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["field", "error"]

  validateField(event) {
    const field = event.target
    const value = field.value.trim()
    const errorTarget = this.errorTargets.find(
      t => t.dataset.field === field.name
    )
    
    if (value.length === 0) {
      errorTarget.textContent = "This field is required"
      field.classList.add('border-red-500')
    } else {
      errorTarget.textContent = ""
      field.classList.remove('border-red-500')
    }
  }
}
```

### 3. Dropdown Menus & Toggles

Local state changes without server round-trip:

```javascript
// app/javascript/controllers/dropdown_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "button"]

  toggle(event) {
    event.preventDefault()
    this.menuTarget.classList.toggle('hidden')
    this.buttonTarget.classList.toggle('active')
  }

  close() {
    this.menuTarget.classList.add('hidden')
    this.buttonTarget.classList.remove('active')
  }
}
```

## Common Patterns

### Pattern 1: Turbo Stream with Fallback

```ruby
def create
  @item = build_item
  
  if @item.save
    respond_to do |format|
      format.turbo_stream  # Real-time update
      format.html { redirect_to @item.list }  # Fallback
    end
  else
    render :new
  end
end
```

### Pattern 2: Broadcast Only to Specific Users

```ruby
def broadcast_to_list_collaborators(action)
  # Only notify collaborators, not the actor
  target_users = list.collaborators.where.not(id: Current.user.id)
  target_users << list.owner unless list.owner == Current.user
  
  target_users.each do |user|
    Turbo::StreamsChannel.broadcast_render_to(
      "list_#{list.id}_user_#{user.id}",
      template: "list_items/#{action}",
      locals: { item: self, list: list }
    )
  end
end
```

### Pattern 3: Batch Updates

```ruby
# Don't broadcast on every change, batch them
after_update_commit :broadcast_changes_later

def broadcast_changes_later
  BroadcastChangesJob.set(wait: 2.seconds).perform_later(self)
end
```

## Subscribing to Streams

### In Views (Turbo Frames)

```erb
<!-- app/views/lists/show.html.erb -->
<%= turbo_frame_tag "list_items_#{@list.id}" do %>
  <!-- Items rendered here -->
  <%= render @list.list_items %>
<% end %>

<!-- Subscribe to real-time updates for this frame -->
<%= turbo_stream_from "list_#{@list.id}_user_#{current_user.id}" %>
```

### Multiple Streams

```erb
<%= turbo_stream_from "list_#{@list.id}_user_#{current_user.id}" %>
<%= turbo_stream_from "notifications_user_#{current_user.id}" %>
<%= turbo_stream_from "user_presence_#{@list.id}" %>
```

## Testing Real-Time Features

### Test Broadcasting

```ruby
# spec/models/list_item_spec.rb
describe ListItem do
  describe "#broadcast_created" do
    it "broadcasts to list collaborators" do
      list = create(:list)
      user = create(:user)
      list.collaborators << user
      
      expect {
        list.list_items.create!(title: "New item")
      }.to have_broadcasted_to("list_#{list.id}_user_#{user.id}")
    end
  end
end
```

### Test Stream Responses

```ruby
# spec/requests/list_items_spec.rb
describe "ListItem creation with Turbo Streams" do
  it "responds with turbo stream" do
    list = create(:list, owner: current_user)
    
    post list_items_path(list), params: {
      list_item: { title: "New task" }
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    
    expect(response.status).to eq(200)
    expect(response.media_type).to match("text/vnd.turbo-stream")
    expect(response.body).to include("turbo-stream")
  end
end
```

## Debugging

### Check Broadcasting

```ruby
# In Rails console
user = User.first
list = List.first

# Trigger broadcast
list.list_items.first.update(title: "Debug test")

# Check broadcast was sent
# Look in browser console or network tab for Turbo Stream messages
```

### Monitor WebSocket

```javascript
// In browser console
// Check connection
console.log(Turbo.session)

// Listen for stream events
document.addEventListener('turbo:before-stream-render', (event) => {
  console.log('Turbo Stream:', event.target.innerHTML)
})
```

## When to Use Stimulus (Not Turbo Streams)

✅ **Use Stimulus when:**
- Interacting with third-party libraries (drag-and-drop, charts, maps)
- Complex local state management without server changes
- Form validation with real-time feedback
- Animations and transitions
- Preventing default browser behavior

❌ **Don't use Stimulus for:**
- Data updates that persist to server
- Rendering updated content from server
- Broadcasting changes to other users
- Multi-user synchronization

Use Turbo Streams instead.

## Performance

### Broadcasting Best Practices

1. **Batch rapid changes** - Use `after_commit` with job delays
2. **Only update needed elements** - Use targeted selectors, not full page
3. **Exclude unnecessary users** - Only broadcast to affected users
4. **Use connection pooling** - Configure Action Cable for production

### Optimization Example

```ruby
# Instead of broadcasting on every keystroke
after_update_commit :broadcast_description_change

# Batch updates with a job
def broadcast_description_change
  BroadcastChangesJob.set(wait: 1.second).perform_later(
    list_id: list.id,
    user_id: Current.user.id
  )
end
```

## Troubleshooting

**Turbo Streams not updating?**
- Check `turbo_stream_from` is in the view
- Verify element IDs match between broadcast and DOM
- Check browser console for errors
- Confirm WebSocket connection in Network tab

**JavaScript not running?**
- Verify Stimulus controller file is in `app/javascript/controllers/`
- Check data attributes match controller targets
- Ensure `import_map.json` includes the controller
- Test in browser console: `Stimulus.application.controllers`

**Performance issues?**
- Monitor broadcast frequency - too many updates?
- Use job delays for rapid-fire changes
- Consider pagination for large lists
- Profile with Rails query logs and network tab

## Summary

**Real-time architecture in Listopia:**

1. **Models trigger broadcasts** - `after_commit` callbacks
2. **Broadcasts send Turbo Streams** - HTML over WebSocket
3. **Streams update DOM** - No page refresh needed
4. **Stimulus enhances interactions** - Only when Turbo can't
5. **Progressive enhancement** - Works without JavaScript

This approach provides real-time collaboration with minimal JavaScript complexity while maintaining excellent performance and user experience.