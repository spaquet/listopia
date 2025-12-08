# Chat System Quick Start Guide

## For Developers

### Testing the Chat System

#### 1. Start a Chat Conversation
```ruby
# In Rails console
user = User.first
org = user.organizations.first
chat = Chat.create!(user: user, organization: org)
message = Message.create_user(chat: chat, user: user, content: "Show me users")
```

#### 2. Process the Message
```ruby
# In controller or background job
service = ChatCompletionService.new(chat, message)
result = service.call

if result.success?
  puts "Message: #{result.data.content}"
  puts "Template: #{result.data.template_type}"
end
```

#### 3. Test Tool Calling
```ruby
# Test list_users tool
executor = LLMToolExecutorService.new(
  tool_name: "list_users",
  tool_input: { status: "active", page: 1 },
  user: user,
  organization: org,
  chat_context: chat.build_context
)
result = executor.call

if result.success?
  data = result.data
  puts "Found #{data[:total_count]} users"
  data[:items].each { |u| puts "  - #{u[:name]} (#{u[:email]})" }
end
```

### Understanding the Flow

```
User Types Message
  ↓
ChatsController#create_message
  ↓
Message created in DB
  ↓
ChatCompletionService.call
  ├─ Check routing intent (ChatRoutingService)
  │  └─ If matches → Create navigation message
  │
  └─ If no routing match:
     ├─ Get available tools (LLMToolsService)
     ├─ Call LLM with tools
     ├─ Check if LLM called a tool
     │  └─ If tool call → Execute (LLMToolExecutorService)
     │
     └─ Create response message

Response Message
  ↓
Turbo Stream renders message
  ↓
Frontend detects message type:
  ├─ Navigation → ChatNavigationController navigates
  ├─ Tool result → Display formatted results
  └─ Text → Show markdown
```

## Common Use Cases

### 1. Adding a New Tool

**Step 1:** Define tool in `LLMToolsService`
```ruby
def new_tool_name_tool
  {
    type: "function",
    function: {
      name: "new_tool_name",
      description: "What this tool does",
      parameters: {
        type: "object",
        properties: {
          param1: { type: "string", description: "..." },
          param2: { type: "integer", description: "..." }
        },
        required: ["param1"]
      }
    }
  }
end
```

**Step 2:** Add to `build_tools` array
```ruby
def build_tools
  [
    navigate_tool,
    # ... other tools ...
    new_tool_name_tool  # Add here
  ]
end
```

**Step 3:** Implement execution in `LLMToolExecutorService`
```ruby
def call
  case @tool_name
  when "new_tool_name"
    execute_new_tool_name(@tool_input)
  # ... other cases ...
  end
end

private

def execute_new_tool_name(input)
  # Validate authorization
  authorize_required_permission!

  # Execute operation
  result = perform_operation(input)

  # Return formatted result
  success(data: {
    type: "list",  # or "resource", "search_results"
    resource_type: "SomeType",
    items: result
  })
rescue StandardError => e
  failure(errors: [e.message])
end
```

### 2. Adding a New Navigation Route

In `ChatRoutingService#detect_management_intent`:
```ruby
def detect_management_intent(message)
  message_lower = message.downcase

  # Add this
  if message_match?(message_lower, %w[your keywords here])
    { action: :navigate, path: :route_name, description: "Description" }
  # ... other routes ...
  end
end
```

### 3. Creating a New Message Template

Create `app/views/message_templates/_template_name.html.erb`:
```erb
<div class="template-container">
  <!-- Use `data` variable for template data -->
  <p><%= data[:some_field] %></p>

  <!-- Optional: hidden marker for JavaScript -->
  <div data-tool-result="<%= data.to_json %>"></div>
</div>
```

Set `template_type` when creating message:
```ruby
Message.create_templated(
  chat: @chat,
  template_type: "template_name",
  template_data: { some_field: "value" }
)
```

## Available Tools Reference

### Navigation
```ruby
# Navigate to a page with optional filters
{
  name: "navigate_to_page",
  page: "admin_users|admin_organizations|organization_teams|lists|...",
  filter: { status: "...", role: "...", query: "..." }
}
```

### Listing Resources
```ruby
# List users with filtering
{ name: "list_users", query: "...", status: "...", role: "...", page: 1 }

# List teams
{ name: "list_teams", query: "...", page: 1 }

# List organizations
{ name: "list_organizations", query: "...", status: "...", page: 1 }

# List lists
{ name: "list_lists", query: "...", status: "...", owner: "...", page: 1 }

# Search everything
{ name: "search", query: "...", resource_type: "all|user|list|team|organization", limit: 10 }
```

### Creating Resources
```ruby
# Create user
{ name: "create_user", email: "...", name: "...", role: "member|admin" }

# Create team
{ name: "create_team", name: "...", description: "..." }

# Create list
{ name: "create_list", title: "...", description: "...", team_id: "..." }
```

### Updating Resources
```ruby
# Update user
{ name: "update_user", user_id: "...", name: "...", email: "...", role: "...", status: "..." }

# Update team
{ name: "update_team", team_id: "...", name: "...", description: "..." }

# Suspend user
{ name: "suspend_user", user_id: "...", action: "suspend|unsuspend", reason: "..." }
```

## Message Metadata

When creating messages, use metadata to store tool data:
```ruby
Message.create_assistant(
  chat: chat,
  content: "Found 10 users",
  metadata: {
    tool_call: "list_users",
    rag_sources: [...],
    attachments: [...]
  }
)
```

## Authorization Checks

All tools check authorization using Pundit:
```ruby
# Reading data
authorize(:admin_user, :read?)

# Writing data
authorize(:admin_user, :write?)
authorize(:team, :create?)
authorize(@list, :edit?)
```

## Error Handling

```ruby
# In services, catch and return errors
result = executor.call
if result.failure?
  # Return error message to user
  Message.create_assistant(
    chat: @chat,
    content: "I encountered an error: #{result.errors.first}"
  )
end
```

## Debugging Tips

### 1. Check What Message Was Created
```ruby
chat.messages.last.inspect
# See: id, content, role, template_type, metadata
```

### 2. Inspect Tool Result
```ruby
message = chat.messages.last
puts message.metadata["tool_result"].inspect
```

### 3. Check Routing Detection
```ruby
routing = ChatRoutingService.new(
  user_message: message,
  chat: chat,
  user: user,
  organization: org
).call
puts routing.data.inspect
```

### 4. Test Tool Executor
```ruby
executor = LLMToolExecutorService.new(
  tool_name: "list_users",
  tool_input: { status: "active" },
  user: user,
  organization: org,
  chat_context: context
)
result = executor.call
puts result.inspect
```

### 5. Check Browser Console
```javascript
// See navigation calls
Turbo.visit('/path') in browser console

// Check message elements
document.querySelectorAll('[data-chat-navigation]')
document.querySelectorAll('[data-tool-result]')
```

## Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| Navigation not working | Verify chat-navigation controller is in index.js |
| Tool not being called | Check tool name matches exactly in LLMToolsService |
| Authorization error | Check Pundit policies for the resource type |
| Message not appearing | Check turbo_stream response format, ensure ID matches |
| LLM not using tools | Verify LLM model supports tools (GPT-4, Claude 3+) |
| Template not rendering | Check template file name matches template_type |

## Testing Checklist

- [ ] Chat message is saved to database
- [ ] Message routing detection works
- [ ] Navigation messages redirect correctly
- [ ] Tool execution respects authorization
- [ ] Tool results are formatted properly
- [ ] Message templates render without errors
- [ ] Tool data persists in metadata
- [ ] Multiple tools can be called in sequence
- [ ] Errors are handled gracefully
- [ ] Chat history is preserved

## File Locations

| Component | File |
|-----------|------|
| Main service | `app/services/chat_completion_service.rb` |
| Routing | `app/services/chat_routing_service.rb` |
| Tools definition | `app/services/llm_tools_service.rb` |
| Tool execution | `app/services/llm_tool_executor_service.rb` |
| Frontend controller | `app/javascript/controllers/chat_navigation_controller.js` |
| Chat views | `app/views/chat/_unified_chat.html.erb` |
| Message templates | `app/views/message_templates/_*.html.erb` |

## Performance Optimization

- **Limit message history:** Default 20 messages (adjust in ChatCompletionService)
- **Cache tool results:** Stored in message metadata
- **Paginate list results:** Default 20 per page (configurable)
- **Use policy_scope:** For authorized record filtering
- **Preload associations:** Use `.includes()` in tool executors

## Next: Full LLM Connection

Once you have RubyLLM configured:

1. Test ChatCompletionService with real LLM
2. Verify tool calling format matches your LLM provider
3. Add error handling for LLM API failures
4. Monitor token usage for cost optimization
5. Collect metrics on tool usage

Ready to build? Start with a simple tool or navigation route and test end-to-end!
