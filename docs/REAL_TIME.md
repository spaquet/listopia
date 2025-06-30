# Listopia Real-Time Features Documentation

## Supported Real-Time Scenarios

### **List Collaboration**
1. **Real-time list updates** - Multiple users see changes instantly without refreshing
2. **Live item creation** - New items appear immediately for all collaborators
3. **Instant status changes** - List status updates (draft→active→completed) broadcast live
4. **Live completion tracking** - Progress percentages update in real-time

### **Item Management** 
5. **Item updates** - Title, description, and priority changes appear instantly
6. **Completion toggling** - Check/uncheck items with immediate visual feedback
7. **Item reordering** - Drag-and-drop positioning updates for all users
8. **Assignment changes** - User assignments update live across sessions

### **Collaboration Features**
9. **User presence** - See who's currently viewing/editing lists
10. **Live notifications** - In-app notifications appear without page refresh
11. **Collaboration changes** - New collaborators appear instantly
12. **Permission updates** - Access level changes take effect immediately

### **Progressive Enhancement**
13. **JavaScript-optional core** - Basic functionality works without JavaScript
14. **Enhanced with Turbo** - Rich interactions with Turbo Streams
15. **WebSocket fallback** - Real-time updates with polling fallback
16. **Mobile-responsive** - Touch-friendly real-time interactions

## Overview

Listopia uses **Hotwire** (Turbo + Stimulus) to deliver real-time collaborative experiences without complex JavaScript frameworks. The system provides instant updates, smooth interactions, and maintains progressive enhancement principles.

## Architecture

### Hotwire Stack

- **Turbo Drive** - Fast page navigation without full reloads
- **Turbo Frames** - Independent page sections that update separately  
- **Turbo Streams** - Real-time HTML updates over WebSockets or HTTP
- **Stimulus Controllers** - Progressive JavaScript enhancement

### Real-Time Data Flow

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   User Action   │────│  Rails Controller│────│  Database       │
│   (Create Item) │    │  (Updates Model) │    │  (Persists Data)│
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Turbo Stream   │────│  Broadcast to    │────│  Other Users    │
│  Generation     │    │  Collaborators   │    │  See Updates    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Turbo Streams Implementation

### Broadcasting Updates

```ruby
# app/models/list_item.rb
class ListItem < ApplicationRecord
  belongs_to :list
  
  # Broadcast changes to all list collaborators
  after_create_commit :broadcast_item_created
  after_update_commit :broadcast_item_updated
  after_destroy_commit :broadcast_item_removed

  private

  def broadcast_item_created
    broadcast_to_list_collaborators(:created)
  end

  def broadcast_item_updated
    broadcast_to_list_collaborators(:updated)
  end

  def broadcast_item_removed
    broadcast_to_list_collaborators(:removed)
  end

  def broadcast_to_list_collaborators(action)
    # Get all users who should see this update
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

### Turbo Stream Templates

```erb
<!-- app/views/list_items/created.turbo_stream.erb -->
<%= turbo_stream.append "list_items_#{list.id}" do %>
  <%= render "list_items/item", item: item, list: list %>
<% end %>

<%= turbo_stream.replace "list_progress_#{list.id}" do %>
  <%= render "lists/progress_bar", list: list %>
<% end %>

<%= turbo_stream.prepend "notifications" do %>
  <div class="notification success">
    <%= item.title %> added to <%= list.title %>
  </div>
<% end %>
```

```erb
<!-- app/views/list_items/updated.turbo_stream.erb -->
<%= turbo_stream.replace "list_item_#{item.id}" do %>
  <%= render "list_items/item", item: item, list: list %>
<% end %>

<%= turbo_stream.replace "list_progress_#{list.id}" do %>
  <%= render "lists/progress_bar", list: list %>
<% end %>
```

```erb
<!-- app/views/list_items/removed.turbo_stream.erb -->
<%= turbo_stream.remove "list_item_#{item.id}" %>

<%= turbo_stream.replace "list_progress_#{list.id}" do %>
  <%= render "lists/progress_bar", list: list %>
<% end %>
```

### Controller Integration

```ruby
# app/controllers/list_items_controller.rb
class ListItemsController < ApplicationController
  def create
    @list = current_user.lists.find(params[:list_id])
    @item = @list.list_items.build(item_params)
    
    if @item.save
      # Turbo Stream response for real-time update
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
    @item.update(completed: !@item.completed, completed_at: @item.completed? ? nil : Time.current)
    
    # Instant response for immediate feedback
    respond_to do |format|
      format.turbo_stream
      format.json { render json: { completed: @item.completed } }
    end
  end
end
```

## Stimulus Controllers

### Real-Time List Management

```javascript
// app/javascript/controllers/list_management_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "progress", "addForm"]
  static values = { listId: String, userId: String }

  connect() {
    // Subscribe to real-time updates for this list
    this.subscribeToUpdates()
  }

  disconnect() {
    // Clean up subscriptions
    this.unsubscribeFromUpdates()
  }

  // Handle item completion toggle
  toggleCompletion(event) {
    const checkbox = event.target
    const itemId = checkbox.dataset.itemId
    
    // Optimistic UI update
    this.updateItemVisually(checkbox, checkbox.checked)
    
    // Send request to server
    fetch(`/list_items/${itemId}/toggle_completion`, {
      method: 'PATCH',
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        'Accept': 'text/vnd.turbo-stream.html'
      }
    })
    .then(response => response.text())
    .then(html => Turbo.renderStreamMessage(html))
    .catch(() => {
      // Revert optimistic update on error
      this.updateItemVisually(checkbox, !checkbox.checked)
    })
  }

  // Add new item with real-time feedback
  addItem(event) {
    event.preventDefault()
    const form = event.target
    const formData = new FormData(form)
    
    // Show loading state
    this.showLoadingState()
    
    fetch(form.action, {
      method: 'POST',
      body: formData,
      headers: {
        'Accept': 'text/vnd.turbo-stream.html',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    })
    .then(response => response.text())
    .then(html => {
      Turbo.renderStreamMessage(html)
      form.reset()
      this.hideLoadingState()
    })
    .catch(error => {
      console.error('Error adding item:', error)
      this.hideLoadingState()
    })
  }

  // Optimistic UI updates
  updateItemVisually(checkbox, completed) {
    const item = checkbox.closest('[data-list-management-target="item"]')
    if (completed) {
      item.classList.add('completed')
    } else {
      item.classList.remove('completed')
    }
  }

  showLoadingState() {
    this.addFormTarget.classList.add('loading')
  }

  hideLoadingState() {
    this.addFormTarget.classList.remove('loading')
  }

  subscribeToUpdates() {
    // Subscribe to Turbo Stream updates for this list
    if (window.Turbo) {
      this.streamSource = new EventSource(`/lists/${this.listIdValue}/stream`)
      this.streamSource.addEventListener('message', (event) => {
        Turbo.renderStreamMessage(event.data)
      })
    }
  }

  unsubscribeFromUpdates() {
    if (this.streamSource) {
      this.streamSource.close()
    }
  }
}
```

### Drag and Drop Reordering

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
      ghostClass: 'sortable-ghost',
      chosenClass: 'sortable-chosen',
      dragClass: 'sortable-drag',
      onEnd: this.handleReorder.bind(this)
    })
  }

  disconnect() {
    if (this.sortable) {
      this.sortable.destroy()
    }
  }

  async handleReorder(event) {
    const itemId = event.item.dataset.itemId
    const newPosition = event.newIndex
    
    try {
      const response = await fetch(`${this.urlValue}/reorder`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Accept': 'text/vnd.turbo-stream.html'
        },
        body: JSON.stringify({
          item_id: itemId,
          position: newPosition
        })
      })
      
      if (response.ok) {
        const html = await response.text()
        Turbo.renderStreamMessage(html)
      }
    } catch (error) {
      console.error('Reorder failed:', error)
      // Could revert the UI change here
    }
  }
}
```

### Real-Time Notifications

```javascript
// app/javascript/controllers/notifications_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["badge", "list", "item"]

  connect() {
    // Subscribe to notification streams
    this.subscribeToNotifications()
  }

  // Mark notification as read
  markAsRead(event) {
    const notificationId = event.currentTarget.dataset.notificationId
    
    fetch(`/notifications/${notificationId}/mark_as_read`, {
      method: 'PATCH',
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        'Accept': 'text/vnd.turbo-stream.html'
      }
    })
    .then(response => response.text())
    .then(html => Turbo.renderStreamMessage(html))
  }

  // Mark all notifications as read
  markAllAsRead(event) {
    event.preventDefault()
    
    fetch('/notifications/mark_all_as_read', {
      method: 'PATCH',
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        'Accept': 'text/vnd.turbo-stream.html'
      }
    })
    .then(response => response.text())
    .then(html => Turbo.renderStreamMessage(html))
  }

  subscribeToNotifications() {
    // Real-time notification updates
    if (window.ActionCable) {
      this.subscription = window.ActionCable.createSubscription('NotificationsChannel', {
        received: (data) => {
          this.handleNewNotification(data)
        }
      })
    }
  }

  handleNewNotification(data) {
    // Update notification badge
    if (this.hasBadgeTarget) {
      const count = parseInt(this.badgeTarget.textContent) + 1
      this.badgeTarget.textContent = count
      this.badgeTarget.classList.remove('hidden')
    }

    // Show toast notification
    this.showToastNotification(data.message, data.type)
  }

  showToastNotification(message, type = 'info') {
    const toast = document.createElement('div')
    toast.className = `notification-toast notification-${type}`
    toast.innerHTML = `
      <div class="notification-content">
        <span>${message}</span>
        <button onclick="this.parentElement.parentElement.remove()">×</button>
      </div>
    `
    
    document.body.appendChild(toast)
    
    // Auto-remove after 5 seconds
    setTimeout(() => toast.remove(), 5000)
  }
}
```

## WebSocket Integration

### Action Cable Setup

```ruby
# app/channels/list_channel.rb
class ListChannel < ApplicationCable::Channel
  def subscribed
    list = List.find(params[:list_id])
    
    # Verify user has access to this list
    if list.readable_by?(current_user)
      stream_for list
      
      # Track user presence
      track_user_presence(list)
    else
      reject
    end
  end

  def unsubscribed
    # Clean up user presence
    remove_user_presence
  end

  def receive(data)
    # Handle real-time actions like typing indicators
    case data['action']
    when 'typing'
      broadcast_typing_indicator(data)
    when 'cursor_position'
      broadcast_cursor_position(data)
    end
  end

  private

  def track_user_presence(list)
    # Store user presence in Redis or memory
    Redis.current.sadd("list_#{list.id}_active_users", current_user.id)
    Redis.current.expire("list_#{list.id}_active_users", 30.seconds)
    
    # Broadcast user joined
    ListChannel.broadcast_to(
      list,
      type: 'user_presence',
      action: 'joined',
      user: {
        id: current_user.id,
        name: current_user.name,
        avatar: current_user.avatar_url
      }
    )
  end

  def remove_user_presence
    # Remove from active users
    Redis.current.srem("list_#{@list.id}_active_users", current_user.id)
    
    # Broadcast user left
    ListChannel.broadcast_to(
      @list,
      type: 'user_presence',
      action: 'left',
      user: { id: current_user.id }
    )
  end
end
```

### JavaScript WebSocket Client

```javascript
// app/javascript/controllers/realtime_controller.js
import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

export default class extends Controller {
  static values = { 
    listId: String, 
    userId: String,
    websocketEnabled: Boolean 
  }

  connect() {
    if (this.websocketEnabledValue) {
      this.connectWebSocket()
    } else {
      // Fallback to polling for updates
      this.startPolling()
    }
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
    
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval)
    }
  }

  connectWebSocket() {
    this.subscription = consumer.subscriptions.create(
      { 
        channel: "ListChannel", 
        list_id: this.listIdValue 
      },
      {
        connected: () => {
          console.log('Connected to ListChannel')
          this.handleConnectionStatus(true)
        },

        disconnected: () => {
          console.log('Disconnected from ListChannel')
          this.handleConnectionStatus(false)
        },

        received: (data) => {
          this.handleRealtimeUpdate(data)
        }
      }
    )
  }

  handleRealtimeUpdate(data) {
    switch (data.type) {
      case 'turbo_stream':
        Turbo.renderStreamMessage(data.html)
        break
      case 'user_presence':
        this.updateUserPresence(data)
        break
      case 'typing_indicator':
        this.showTypingIndicator(data)
        break
      case 'notification':
        this.showNotification(data)
        break
    }
  }

  updateUserPresence(data) {
    const presenceIndicator = document.querySelector('#user-presence')
    if (!presenceIndicator) return

    if (data.action === 'joined') {
      this.addUserToPresence(data.user)
    } else if (data.action === 'left') {
      this.removeUserFromPresence(data.user.id)
    }
  }

  addUserToPresence(user) {
    const presenceList = document.querySelector('#active-users')
    if (presenceList && !document.querySelector(`[data-user-id="${user.id}"]`)) {
      const userElement = document.createElement('div')
      userElement.className = 'active-user'
      userElement.dataset.userId = user.id
      userElement.innerHTML = `
        <img src="${user.avatar || '/default-avatar.png'}" 
             alt="${user.name}" 
             class="w-8 h-8 rounded-full border-2 border-green-400"
             title="${user.name} is viewing this list">
      `
      presenceList.appendChild(userElement)
    }
  }

  removeUserFromPresence(userId) {
    const userElement = document.querySelector(`[data-user-id="${userId}"]`)
    if (userElement) {
      userElement.remove()
    }
  }

  startPolling() {
    this.pollingInterval = setInterval(() => {
      this.checkForUpdates()
    }, 10000) // Poll every 10 seconds
  }

  async checkForUpdates() {
    try {
      const response = await fetch(`/lists/${this.listIdValue}/updates`, {
        headers: {
          'Accept': 'text/vnd.turbo-stream.html',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      
      if (response.ok) {
        const html = await response.text()
        if (html.trim()) {
          Turbo.renderStreamMessage(html)
        }
      }
    } catch (error) {
      console.warn('Polling update failed:', error)
    }
  }

  handleConnectionStatus(connected) {
    const indicator = document.querySelector('#connection-status')
    if (indicator) {
      indicator.className = connected ? 'connected' : 'disconnected'
      indicator.textContent = connected ? 'Connected' : 'Reconnecting...'
    }
  }
}
```

## Progressive Enhancement

### Core Functionality Without JavaScript

```erb
<!-- app/views/lists/show.html.erb -->
<div data-controller="list-management realtime" 
     data-list-management-list-id-value="<%= @list.id %>"
     data-realtime-list-id-value="<%= @list.id %>"
     data-realtime-user-id-value="<%= current_user.id %>"
     data-realtime-websocket-enabled-value="<%= Rails.env.production? %>">

  <!-- Works without JavaScript -->
  <%= form_with model: [@list, ListItem.new], 
                local: true, 
                data: { 
                  action: "turbo:submit-end->list-management#addItem",
                  list_management_target: "addForm" 
                } do |f| %>
    <%= f.text_field :title, placeholder: "Add new item...", required: true %>
    <%= f.submit "Add Item", class: "btn btn-primary" %>
  <% end %>

  <!-- Items list - enhanced with Turbo Streams -->
  <div id="list_items_<%= @list.id %>" 
       data-controller="sortable"
       data-sortable-url-value="<%= list_list_items_path(@list) %>">
    <%= render @list.list_items %>
  </div>
</div>
```

### Turbo Frame Enhanced Sections

```erb
<!-- app/views/list_items/_item.html.erb -->
<%= turbo_frame_tag "list_item_#{item.id}", 
                    data: { 
                      list_management_target: "item",
                      item_id: item.id 
                    } do %>
  <div class="list-item <%= 'completed' if item.completed? %>">
    <!-- Quick completion toggle -->
    <%= form_with model: [item.list, item], 
                  url: toggle_completion_list_list_item_path(item.list, item),
                  method: :patch,
                  data: { 
                    action: "change->list-management#toggleCompletion",
                    turbo_method: "patch"
                  } do |f| %>
      <%= f.check_box :completed, 
                      checked: item.completed?,
                      data: { item_id: item.id },
                      onchange: "this.form.requestSubmit()" %>
    <% end %>

    <!-- Item content -->
    <div class="item-content">
      <h4><%= item.title %></h4>
      <% if item.description.present? %>
        <p><%= item.description %></p>
      <% end %>
    </div>

    <!-- Edit link - loads in Turbo Frame -->
    <%= link_to "Edit", 
                edit_list_list_item_path(item.list, item),
                data: { turbo_frame: "list_item_#{item.id}" } %>
  </div>
<% end %>
```

### Mobile-Responsive Real-Time

```scss
// app/assets/stylesheets/real_time.scss
.list-item {
  @apply p-4 border border-gray-200 rounded-lg mb-2 transition-all duration-200;
  
  &.completed {
    @apply opacity-60 bg-gray-50;
    
    .item-content {
      @apply line-through;
    }
  }
  
  // Touch-friendly targets on mobile
  @screen max-sm {
    @apply p-6 text-lg;
    
    input[type="checkbox"] {
      @apply w-6 h-6;
    }
  }
}

// Real-time feedback animations
.sortable-ghost {
  @apply opacity-40;
}

.sortable-chosen {
  @apply ring-2 ring-blue-500;
}

// Connection status indicator
#connection-status {
  @apply fixed top-4 right-4 px-3 py-1 rounded-full text-sm font-medium;
  
  &.connected {
    @apply bg-green-100 text-green-800;
  }
  
  &.disconnected {
    @apply bg-red-100 text-red-800;
  }
}

// User presence indicators
#user-presence {
  .active-user {
    @apply inline-block mr-2;
    
    img {
      @apply animate-pulse;
    }
  }
}
```

## Performance Optimization

### Efficient Broadcasting

```ruby
# app/models/concerns/broadcastable.rb
module Broadcastable
  extend ActiveSupport::Concern

  private

  def broadcast_to_list_collaborators(action, **options)
    # Batch database queries for efficiency
    collaborator_ids = list.list_collaborations
                          .includes(:user)
                          .pluck(:user_id)
                          .compact
    
    owner_id = list.user_id
    target_user_ids = ([owner_id] + collaborator_ids).uniq
    
    # Batch broadcast to reduce individual renders
    target_user_ids.each do |user_id|
      broadcast_later_to(
        "list_#{list.id}_user_#{user_id}",
        action: action,
        item: self,
        list: list,
        **options
      )
    end
  end

  def broadcast_later_to(stream_name, **options)
    # Use background jobs for broadcasting to avoid blocking requests
    BroadcastJob.perform_later(stream_name, **options)
  end
end
```

### Background Broadcasting

```ruby
# app/jobs/broadcast_job.rb
class BroadcastJob < ApplicationJob
  queue_as :default

  def perform(stream_name, action:, item:, list:, **options)
    template_path = "list_items/#{action}"
    
    Turbo::StreamsChannel.broadcast_render_to(
      stream_name,
      template: template_path,
      locals: { 
        item: item, 
        list: list,
        **options 
      }
    )
  end
end
```

### Caching Strategies

```ruby
# app/models/list.rb
class List < ApplicationRecord
  # Cache expensive progress calculations
  def completion_percentage
    Rails.cache.fetch("list_#{id}_completion", expires_in: 5.minutes) do
      return 0 if list_items.empty?
      
      completed_count = list_items.where(completed: true).count
      total_count = list_items.count
      
      (completed_count.to_f / total_count * 100).round(1)
    end
  end

  # Invalidate cache when items change
  def invalidate_progress_cache
    Rails.cache.delete("list_#{id}_completion")
  end
end

# Invalidate cache on item changes
class ListItem < ApplicationRecord
  after_save :invalidate_list_cache
  after_destroy :invalidate_list_cache

  private

  def invalidate_list_cache
    list.invalidate_progress_cache
  end
end
```

## Testing Real-Time Features

### System Tests with Turbo

```ruby
# spec/system/real_time_collaboration_spec.rb
require 'rails_helper'

RSpec.describe "Real-time Collaboration", type: :system, js: true do
  let(:owner) { create(:user, :verified) }
  let(:collaborator) { create(:user, :verified) }
  let(:list) { create(:list, owner: owner) }

  before do
    list.list_collaborations.create!(user: collaborator, permission: :collaborate)
  end

  scenario "Users see real-time item creation" do
    using_session("owner") do
      sign_in_with_ui(owner)
      visit list_path(list)
    end

    using_session("collaborator") do
      sign_in_with_ui(collaborator)
      visit list_path(list)
      
      # Wait for WebSocket connection
      expect(page).to have_css('#connection-status.connected', wait: 5)
    end

    using_session("owner") do
      fill_in "Title", with: "New Task"
      click_button "Add Item"
      
      expect(page).to have_content("New Task")
    end

    using_session("collaborator") do
      # Should see the new item without refresh
      expect(page).to have_content("New Task", wait: 3)
    end
  end

  scenario "Progress updates in real-time" do
    item = create(:list_item, list: list, completed: false)

    using_session("owner") do
      sign_in_with_ui(owner)
      visit list_path(list)
    end

    using_session("collaborator") do
      sign_in_with_ui(collaborator)
      visit list_path(list)
    end

    using_session("owner") do
      check "list_item_#{item.id}_completed"
      
      # Progress should update
      expect(page).to have_css(".progress-bar[data-percentage='100']")
    end

    using_session("collaborator") do
      # Should see progress update
      expect(page).to have_css(".progress-bar[data-percentage='100']", wait: 3)
    end
  end
end
```

### Stimulus Controller Tests

```javascript
// spec/javascript/controllers/list_management_controller.test.js
import { Application } from "@hotwired/stimulus"
import ListManagementController from "../../app/javascript/controllers/list_management_controller"

describe("ListManagementController", () => {
  let application
  let controller
  let element

  beforeEach(() => {
    document.body.innerHTML = `
      <div data-controller="list-management"
           data-list-management-list-id-value="123"
           data-list-management-user-id-value="456">
        <div data-list-management-target="item" data-item-id="1">
          <input type="checkbox" data-action="change->list-management#toggleCompletion">
        </div>
      </div>
    `

    application = Application.start()
    application.register("list-management", ListManagementController)
    element = document.querySelector('[data-controller="list-management"]')
    controller = application.getControllerForElementAndIdentifier(element, "list-management")
  })

  afterEach(() => {
    application.stop()
  })

  test("toggles item completion optimistically", () => {
    const checkbox = element.querySelector('input[type="checkbox"]')
    const item = element.querySelector('[data-list-management-target="item"]')
    
    // Mock fetch
    global.fetch = jest.fn(() => Promise.resolve({ 
      ok: true,
      text: () => Promise.resolve('<turbo-stream>...</turbo-stream>')
    }))

    checkbox.checked = true
    checkbox.dispatchEvent(new Event('change'))

    expect(item.classList.contains('completed')).toBe(true)
    expect(fetch).toHaveBeenCalledWith(
      '/list_items/1/toggle_completion',
      expect.objectContaining({ method: 'PATCH' })
    )
  })
})
```

## Error Handling & Fallbacks

### Connection Resilience

```javascript
// app/javascript/controllers/connection_monitor_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { retryInterval: { type: Number, default: 5000 } }

  connect() {
    this.setupConnectionMonitoring()
  }

  setupConnectionMonitoring() {
    // Monitor WebSocket connection
    if (window.ActionCable) {
      window.ActionCable.adapters.WebSocket.prototype.open = 
        this.wrapWebSocketOpen(window.ActionCable.adapters.WebSocket.prototype.open)
    }

    // Monitor Turbo connection
    document.addEventListener('turbo:fetch-request-error', this.handleTurboError.bind(this))
  }

  wrapWebSocketOpen(originalOpen) {
    return function() {
      this.addEventListener('open', () => {
        document.dispatchEvent(new CustomEvent('websocket:connected'))
      })

      this.addEventListener('close', () => {
        document.dispatchEvent(new CustomEvent('websocket:disconnected'))
        this.scheduleReconnection()
      })

      this.addEventListener('error', () => {
        document.dispatchEvent(new CustomEvent('websocket:error'))
      })

      return originalOpen.apply(this, arguments)
    }
  }

  handleTurboError(event) {
    // Show user-friendly error message
    this.showErrorNotification('Connection issue. Changes may not be saved.')
    
    // Attempt to retry after delay
    setTimeout(() => {
      event.detail.resume()
    }, this.retryIntervalValue)
  }

  scheduleReconnection() {
    setTimeout(() => {
      if (window.ActionCable && window.ActionCable.consumer) {
        window.ActionCable.consumer.connect()
      }
    }, this.retryIntervalValue)
  }

  showErrorNotification(message) {
    const notification = document.createElement('div')
    notification.className = 'notification error'
    notification.textContent = message
    document.body.appendChild(notification)
    
    setTimeout(() => notification.remove(), 5000)
  }
}
```

### Graceful Degradation

```ruby
# app/controllers/concerns/real_time_fallbacks.rb
module RealTimeFallbacks
  extend ActiveSupport::Concern

  private

  def respond_with_real_time_fallback
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back_or_to(fallback_location) }
      format.json { render json: { status: 'success' } }
    end
  end

  def fallback_location
    request.referer || root_path
  end
end
```

## Troubleshooting

### Common Real-Time Issues

**1. Turbo Streams not updating**
```ruby
# Check if Turbo is loaded
Turbo.session.drive # Should return true

# Verify correct stream targeting
<%= turbo_stream.replace "list_item_#{item.id}" do %>
  <!-- Content -->
<% end %>

# Ensure element exists with correct ID
<div id="list_item_<%= item.id %>">...</div>
```

**2. WebSocket connection failures**
```javascript
// Check connection status
consumer.subscriptions.subscriptions[0].consumer.connection.isOpen()

// Monitor connection events
consumer.subscriptions.subscriptions[0].consumer.connection.events
```

**3. Performance issues with broadcasting**
```ruby
# Use background jobs for expensive broadcasts
after_commit :broadcast_changes_later

def broadcast_changes_later
  BroadcastChangesJob.perform_later(self)
end
```

**4. Mobile touch issues**
```scss
// Ensure touch targets are large enough
.interactive-element {
  min-height: 44px; /* iOS minimum touch target */
  min-width: 44px;
}

// Handle touch events properly
@media (hover: none) {
  .hover-effect:hover {
    /* Remove hover effects on touch devices */
  }
}
```

### Debugging Tools

```javascript
// Debug Turbo Streams
document.addEventListener('turbo:before-stream-render', (event) => {
  console.log('Turbo Stream:', event.target.innerHTML)
})

// Debug Action Cable
ActionCable.logger.enabled = true

// Monitor WebSocket messages
consumer.subscriptions.subscriptions[0].consumer.connection.monitor.recordPing = function() {
  console.log('WebSocket ping:', Date.now())
  return this.recordPingOrig.apply(this, arguments)
}
```

## Future Enhancements

### Planned Real-Time Features

1. **Collaborative editing** - Real-time text editing with operational transforms
2. **Voice/video calls** - WebRTC integration for team collaboration
3. **Screen sharing** - Share screens during list planning sessions
4. **Real-time cursors** - See where other users are working
5. **Advanced presence** - Status indicators, typing notifications

### Performance Improvements

- **Connection pooling** - Optimize WebSocket connections
- **Message batching** - Reduce broadcast frequency for rapid changes
- **Smart reconnection** - Exponential backoff for connection retries
- **Bandwidth optimization** - Compress payloads for mobile users

## Summary

Listopia's real-time features provide a seamless collaborative experience using modern web technologies:

**Key Technologies:**
- **Hotwire Turbo Streams** - HTML-over-the-wire real-time updates
- **Stimulus Controllers** - Progressive JavaScript enhancement
- **Action Cable** - WebSocket connections for instant communication
- **Progressive Enhancement** - Works without JavaScript, enhanced with it

**Real-Time Capabilities:**
- **Instant collaboration** - Multiple users see changes immediately
- **Optimistic UI** - Immediate feedback with server confirmation
- **Presence awareness** - See who's actively viewing lists
- **Mobile-responsive** - Touch-friendly real-time interactions

**Performance Features:**
- **Background broadcasting** - Non-blocking real-time updates
- **Efficient caching** - Smart cache invalidation strategies
- **Graceful fallbacks** - Polling backup when WebSockets fail
- **Error resilience** - Automatic reconnection and retry logic

This architecture provides a solid foundation for real-time collaboration that scales with user needs while maintaining excellent performance and user experience.