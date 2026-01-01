# Chat Features & Implementation Guide

A comprehensive guide for implementing and extending chat features in Listopia. This guide covers architecture, common patterns, and how to add new capabilities to the chat system.

**For system architecture overview, see [CLAUDE.md - Chat System Architecture](CLAUDE.md#chat-system-architecture)**

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Architecture Overview](#architecture-overview)
3. [How to Add Features](#how-to-add-features)
4. [Available Tools Reference](#available-tools-reference)
5. [Message Templates](#message-templates)
6. [Authorization & Security](#authorization--security)
7. [Testing Scenarios](#testing-scenarios)
8. [Debugging & Troubleshooting](#debugging--troubleshooting)
9. [Common Issues & Solutions](#common-issues--solutions)
10. [File Locations](#file-locations)

---

## Quick Start

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

---

## Architecture Overview

### Message Flow Diagram

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

### Core Services

| Service | Purpose | File |
|---------|---------|------|
| `ChatCompletionService` | Main message processing orchestrator | `app/services/chat_completion_service.rb` |
| `ChatRoutingService` | Detects navigation intents | `app/services/chat_routing_service.rb` |
| `LLMToolsService` | Defines available tools | `app/services/llm_tools_service.rb` |
| `LLMToolExecutorService` | Executes tool calls | `app/services/llm_tool_executor_service.rb` |
| `ChatMentionParser` | Parses @mentions and #references | `app/services/chat_mention_parser.rb` |
| `ContentModerationService` | OpenAI content moderation | `app/services/content_moderation_service.rb` |
| `PromptInjectionDetector` | Detects injection attempts | `app/services/prompt_injection_detector.rb` |

---

## How to Add Features

### 1. Adding a New Command (e.g., /search, /help)

**Step 1:** Define command in controller or service

```ruby
# Commands are typically processed in ChatCompletionService
case command_name
when "search"
  SearchService.call(query: args[:q], user: user, organization: organization)
when "help"
  display_available_commands
when "browse"
  list_accessible_lists
end
```

**Step 2:** Add to command hints (UI)

Commands appear in the chat input via the Stimulus controller:

```javascript
// app/javascript/controllers/unified_chat_controller.js
// Update AVAILABLE_COMMANDS
const AVAILABLE_COMMANDS = [
  { name: "search", description: "Search lists and items", args: "<query>" },
  { name: "help", description: "Show available commands", args: "" },
  { name: "browse", description: "Browse your lists", args: "[status]" }
];
```

**Step 3:** Create message template if needed

```erb
<!-- app/views/message_templates/_command_result.html.erb -->
<div class="command-result">
  <%= data[:result] %>
</div>
```

**Step 4:** Test the command

```ruby
# In Rails console
message = Message.create_user(chat: chat, user: user, content: "/search budget")
service = ChatCompletionService.new(chat, message)
result = service.call
puts result.data.content
```

---

### 2. Adding a New LLM Tool

**Step 1:** Define tool in `LLMToolsService`

```ruby
# app/services/llm_tools_service.rb

def my_custom_tool_tool
  {
    type: "function",
    function: {
      name: "my_custom_tool",
      description: "What this tool does in detail",
      parameters: {
        type: "object",
        properties: {
          param1: {
            type: "string",
            description: "Description of param1"
          },
          param2: {
            type: "integer",
            description: "Description of param2"
          }
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
    list_users_tool,
    create_user_tool,
    # ... other tools ...
    my_custom_tool_tool  # Add here
  ]
end
```

**Step 3:** Implement execution in `LLMToolExecutorService`

```ruby
def call
  case @tool_name
  when "my_custom_tool"
    execute_my_custom_tool(@tool_input)
  # ... other cases ...
  end
end

private

def execute_my_custom_tool(input)
  # Validate authorization
  authorize_required_permission!

  # Execute operation
  result = perform_operation(input)

  # Return formatted result
  success(data: {
    type: "list",  # or "resource", "search_results"
    resource_type: "SomeType",
    items: result,
    total_count: result.count
  })
rescue StandardError => e
  failure(errors: [e.message])
end
```

**Step 4:** Test the tool

```ruby
executor = LLMToolExecutorService.new(
  tool_name: "my_custom_tool",
  tool_input: { param1: "value", param2: 42 },
  user: user,
  organization: org,
  chat_context: context
)
result = executor.call
puts result.success? ? "Success!" : result.errors.inspect
```

---

### 3. Adding a New Message Template

**Step 1:** Create template file

```erb
<!-- app/views/message_templates/_my_template.html.erb -->
<div class="template-container">
  <div class="card">
    <h3><%= data[:title] %></h3>
    <p><%= data[:description] %></p>

    <!-- Optional: hidden marker for JavaScript to detect template -->
    <div data-template-type="my_template" data-tool-result="<%= data.to_json %>"></div>
  </div>
</div>
```

**Step 2:** Register in MessageTemplate class (optional)

```ruby
# app/models/message_template.rb
REGISTRY = {
  # ... existing templates ...
  "my_template" => MyTemplateTemplate
}
```

**Step 3:** Create message with template

```ruby
Message.create_templated(
  chat: @chat,
  user: @user,
  template_type: "my_template",
  template_data: {
    title: "Example",
    description: "This is a template"
  }
)
```

**Step 4:** Test template rendering

Open chat and trigger message creation:
```ruby
# Rails console
msg = Message.create_templated(
  chat: Chat.first,
  template_type: "my_template",
  template_data: { title: "Test", description: "Testing" }
)
# Visit chat page and see the message
```

---

### 4. Adding a New Navigation Route

**Step 1:** Add to `ChatRoutingService#detect_management_intent`

```ruby
def detect_management_intent(message)
  message_lower = message.downcase

  # Add this pattern
  if message_match?(message_lower, %w[your keywords here])
    {
      action: :navigate,
      path: :your_route_name,
      filters: { key: "value" },  # Optional
      description: "Navigate to Your Page"
    }
  # ... other routes ...
  end
end
```

**Step 2:** Test routing detection

```ruby
service = ChatRoutingService.new(
  user_message: message,
  chat: chat,
  user: user,
  organization: org
)
result = service.call
puts result.data.inspect  # Should show your route
```

**Step 3:** Verify frontend navigation

The `ChatNavigationController` automatically handles navigation messages.

---

## Available Tools Reference

### Navigation Tool
```ruby
# Navigate to a page with optional filters
{
  name: "navigate_to_page",
  page: "admin_users|admin_organizations|organization_teams|lists",
  filters: { status: "active", role: "admin", query: "..." }
}
```

### Listing Resources

#### List Users
```ruby
{
  name: "list_users",
  query: "search term",      # Optional
  status: "active|suspended",  # Optional
  role: "member|admin",       # Optional
  page: 1                      # Optional
}
```

#### List Teams
```ruby
{
  name: "list_teams",
  query: "search term",
  page: 1
}
```

#### List Organizations
```ruby
{
  name: "list_organizations",
  query: "search term",
  status: "active|archived",
  page: 1
}
```

#### List Lists
```ruby
{
  name: "list_lists",
  query: "search term",
  status: "draft|active|completed|archived",
  owner: "user_id",  # Optional
  team_id: "team_id",  # Optional
  page: 1
}
```

#### Search Everything
```ruby
{
  name: "search",
  query: "search term",
  resource_type: "all|user|list|team|organization",
  limit: 10
}
```

### Creating Resources

#### Create User
```ruby
{
  name: "create_user",
  email: "user@example.com",
  name: "Full Name",
  role: "member|admin"  # Optional
}
```

#### Create Team
```ruby
{
  name: "create_team",
  name: "Team Name",
  description: "Team description"  # Optional
}
```

#### Create List
```ruby
{
  name: "create_list",
  title: "List Title",
  description: "List description",  # Optional
  team_id: "team_id"  # Optional
}
```

### Updating Resources

#### Update User
```ruby
{
  name: "update_user",
  user_id: "uuid",
  name: "New Name",  # Optional
  email: "new@example.com",  # Optional
  role: "member|admin",  # Optional
  status: "active|suspended"  # Optional
}
```

#### Update Team
```ruby
{
  name: "update_team",
  team_id: "uuid",
  name: "New Team Name",  # Optional
  description: "New description"  # Optional
}
```

#### Suspend/Unsuspend User
```ruby
{
  name: "suspend_user",
  user_id: "uuid",
  action: "suspend|unsuspend",
  reason: "Reason for suspension"  # Optional
}
```

---

## Message Templates

### Standard Message Creation Methods

```ruby
# Create user message (user input)
Message.create_user(chat: chat, user: user, content: "Hello")

# Create assistant response
Message.create_assistant(chat: chat, content: "Hi there!")

# Create system message
Message.create_system(chat: chat, content: "System notification")

# Create templated message
Message.create_templated(
  chat: chat,
  template_type: "list_created",
  template_data: { list_id: "uuid", title: "My List" }
)
```

### Available Templates

| Template | Use Case | Data Structure |
|----------|----------|-----------------|
| `user_profile` | Show user information | `{ user_id, name, email, lists_count, teams_count }` |
| `team_summary` | Show team details | `{ team_id, name, members_count, lists_count }` |
| `list_created` | Confirmation of list creation | `{ list_id, title, description }` |
| `items_created` | Confirmation of item creation | `{ list_id, items_count, items }` |
| `search_results` | Display search results | `{ query, results_count, results }` |
| `command_result` | Generic command result | `{ result, command, metadata }` |
| `navigation` | Navigation to page | `{ path, filters, description }` |
| `rag_sources` | RAG context sources | `{ sources, query, relevance_scores }` |
| `error` | Error message | `{ error_message, error_code, recovery_hint }` |
| `success` | Success confirmation | `{ message, action, resource_link }` |

---

## Authorization & Security

### Authorization Checks in Tools

All tools must check authorization using Pundit:

```ruby
def execute_list_users(input)
  # Reading admin data
  authorize(:admin_user, :read?)

  # Return results
  success(data: { ... })
rescue Pundit::NotAuthorizedError
  failure(errors: ["You don't have permission to access this"])
end
```

### Required Authorization Checks

| Operation | Policy Check |
|-----------|--------------|
| List users | `authorize(:admin_user, :read?)` |
| Create user | `authorize(:admin_user, :write?)` |
| Update user | `authorize(@user, :update?)` |
| List teams | `authorize(:team, :read?)` |
| Create team | `authorize(:team, :create?)` |
| Create list | `authorize(:list, :create?)` |
| Search | Uses `policy_scope(Model)` |

### Organization Boundaries

All queries must be scoped to user's organization:

```ruby
# ✅ Good
organization.users  # Scoped to org
policy_scope(List)  # Uses Pundit scoping

# ❌ Bad
User.all  # No org boundary
List.where(title: "...") # No org boundary
```

### Message Metadata for Security

Sensitive operations should be logged:

```ruby
Message.create_assistant(
  chat: chat,
  content: "Created user john@example.com",
  metadata: {
    tool_call: "create_user",
    user_id: new_user.id,
    security_event: true
  }
)
```

---

## Testing Scenarios

### Test Checklist

- [ ] Chat message is saved to database
- [ ] Message routing detection works correctly
- [ ] Navigation messages redirect to correct pages
- [ ] Tool execution respects authorization (Pundit)
- [ ] Tool results are formatted properly
- [ ] Message templates render without errors
- [ ] Tool data persists in message metadata
- [ ] Multiple tools can be called in sequence
- [ ] Errors are handled gracefully
- [ ] Chat history is preserved
- [ ] Organization boundaries are enforced
- [ ] User cannot access data from different org

### Example Test Specs

#### Test Routing Detection
```ruby
it "detects navigation intent for users page" do
  service = ChatRoutingService.new(
    user_message: @message,
    chat: @chat,
    user: @user,
    organization: @org
  )
  result = service.call

  expect(result.success?).to be true
  expect(result.data[:path]).to eq :admin_users
end
```

#### Test Tool Execution
```ruby
it "lists active users with proper authorization" do
  executor = LLMToolExecutorService.new(
    tool_name: "list_users",
    tool_input: { status: "active" },
    user: @user,
    organization: @org,
    chat_context: @context
  )
  result = executor.call

  expect(result.success?).to be true
  expect(result.data[:total_count]).to eq 1
  expect(result.data[:items].first[:email]).to eq @user.email
end
```

#### Test Organization Boundary
```ruby
it "prevents access to users from different organization" do
  user_in_other_org = create(:user, organization: @other_org)

  executor = LLMToolExecutorService.new(
    tool_name: "list_users",
    tool_input: {},
    user: user_in_other_org,
    organization: @other_org,
    chat_context: context
  )
  result = executor.call

  # Should only return users from @other_org, not @org
  expect(result.data[:items].map(&:id)).not_to include @user.id
end
```

---

## Debugging & Troubleshooting

### Check Message Status

```ruby
# In Rails console
chat = Chat.first
chat.messages.last.inspect
# See: id, content, role, template_type, metadata
```

### Inspect Tool Result

```ruby
message = chat.messages.last
puts message.metadata["tool_call"]
puts message.metadata["tool_result"].inspect
```

### Check Routing Detection

```ruby
routing = ChatRoutingService.new(
  user_message: message,
  chat: chat,
  user: user,
  organization: org
).call

puts routing.data.inspect
```

### Test Tool Executor Directly

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

### Check Browser Console

```javascript
// See navigation calls
document.querySelectorAll('[data-chat-navigation]')

// Check message elements
document.querySelectorAll('[data-tool-result]')

// Monitor Turbo events
Turbo.addEventListener('turbo:visit', console.log)
```

### Enable Debug Logging

```ruby
# In environment config
config.log_level = :debug

# In service
Rails.logger.debug("Tool execution", { tool: @tool_name, input: @tool_input })
```

---

## Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| Navigation not working | Verify `chat-navigation` controller is in `controllers/index.js` |
| Tool not being called | Check tool name matches exactly in `LLMToolsService` |
| Authorization error | Check Pundit policies for the resource type |
| Message not appearing | Check Turbo Stream response format, ensure container ID matches |
| LLM not using tools | Verify LLM model supports tools (GPT-4, Claude 3+) |
| Template not rendering | Check template file name matches `template_type` exactly |
| Tool results look wrong | Inspect `LLMToolExecutorService` return value formatting |
| Message metadata missing | Check message created with `metadata: { ... }` parameter |
| User can't see results | Verify `policy_scope` is being used or org boundary check |
| Duplicate messages | Check if message creation happens twice in controller/job |

### RubyLLM Not Configured?

```ruby
# Check in Rails console
RubyLLM.models
# Should show available models

# Test a simple call
result = RubyLLM.chat(
  messages: [{ role: "user", content: "Hello" }],
  model: "gpt-4o-mini"
)
```

---

## File Locations

### Core Files

| Component | File | Lines |
|-----------|------|-------|
| Main service | `app/services/chat_completion_service.rb` | ~400 |
| Routing | `app/services/chat_routing_service.rb` | ~200 |
| Tools definition | `app/services/llm_tools_service.rb` | ~450 |
| Tool execution | `app/services/llm_tool_executor_service.rb` | ~550 |
| Mention parsing | `app/services/chat_mention_parser.rb` | ~150 |

### Models

| Model | File |
|-------|------|
| Chat | `app/models/chat.rb` |
| Message | `app/models/message.rb` |
| Message Feedback | `app/models/message_feedback.rb` |
| Chat Context | `app/models/chat_context.rb` |

### Frontend

| Component | File |
|-----------|------|
| Unified chat controller | `app/javascript/controllers/unified_chat_controller.js` |
| Navigation controller | `app/javascript/controllers/chat_navigation_controller.js` |
| Message rating controller | `app/javascript/controllers/message_rating_controller.js` |

### Views

| View | File |
|------|------|
| Main chat view | `app/views/chat/_unified_chat.html.erb` |
| Message rendering | `app/views/shared/_chat_message.html.erb` |
| Message templates | `app/views/message_templates/*.html.erb` |

### Controllers

| Controller | File |
|------------|------|
| Chats | `app/controllers/chats_controller.rb` |
| Chat commands | `app/controllers/chat/commands_controller.rb` |
| Message feedbacks | `app/controllers/chat/message_feedbacks_controller.rb` |

### Tests

| Test | File |
|------|------|
| Chat service specs | `spec/services/chat_completion_service_spec.rb` |
| Tool executor specs | `spec/services/llm_tool_executor_service_spec.rb` |
| Chat system specs | `spec/system/chat_system_spec.rb` |

---

## Performance Optimization

### Message History Limits

```ruby
# In ChatCompletionService
HISTORY_LIMIT = 20  # Number of previous messages to include

# Reduces token usage while maintaining context
messages = @chat.messages.recent(HISTORY_LIMIT)
```

### Caching Tool Results

```ruby
# Store tool results in message metadata
message.metadata = {
  tool_call: "list_users",
  tool_result: { ... },  # Cached here
  cached_at: Time.current
}
```

### Paginating List Results

```ruby
# Default: 20 per page (configurable)
results = paginated_results
  .page(params[:page] || 1)
  .per(20)
```

### Using Policy Scope

```ruby
# Efficiently filters records in single query
@lists = policy_scope(List)
# vs multiple queries
@lists = List.where(organization: @user.organizations)
```

### Preloading Associations

```ruby
# Prevent N+1 queries
@users = organization.users.includes(:organizations, :teams)
```

---

## Next Steps

Once you're familiar with this guide:

1. **Add a simple command** - Start with `/help` or `/clear`
2. **Add a tool** - Try `list_lists` or similar read-only operation
3. **Create a message template** - Practice custom rendering
4. **Add authorization checks** - Ensure security in your implementation
5. **Write tests** - Test your features before merging
6. **Monitor logs** - Track usage and debug issues

For architecture details and system design, see [CLAUDE.md - Chat System Architecture](CLAUDE.md#chat-system-architecture)
