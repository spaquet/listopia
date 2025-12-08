# Listopia Chat System Documentation

## Overview

The Listopia chat system is a unified LLM-powered chat interface that allows users to:
- Ask questions and get responses about their data
- Navigate to existing app pages through natural language (e.g., "Show me active users")
- Create, update, and manage resources (users, teams, organizations, lists)
- Search across the application
- Get real-time suggestions and assistance

The system uses **RubyLLM** for LLM provider abstraction and supports OpenAI, Anthropic Claude, Google Gemini, and other providers.

## Architecture

### Core Components

#### 1. **ChatCompletionService** (`app/services/chat_completion_service.rb`)
Main service that orchestrates the chat flow:
- Receives user messages
- Detects routing intents via `ChatRoutingService`
- Builds message history for context
- Calls LLM with tools support via RubyLLM
- Handles tool call execution
- Creates appropriate message types

**Key Features:**
- Smart routing: Detects when users want to navigate to pages instead of getting chat responses
- Tool calling: Enables LLM to call structured tools for data operations
- Context awareness: Uses ChatContext to provide location-specific behavior
- Error handling: Gracefully handles LLM failures with fallback messages

#### 2. **ChatRoutingService** (`app/services/chat_routing_service.rb`)
Detects user intent to navigate to existing app pages:
- Analyzes user message for navigation keywords
- Matches against management intent patterns
- Returns routing data for frontend navigation

**Supported Routes:**
- Admin users management (`/admin/users`)
- Admin organizations management (`/admin/organizations`)
- Organization teams management (`/organizations/:id/teams`)
- Lists management (`/lists`)
- User profile and settings
- Admin dashboard

#### 3. **LLMToolsService** (`app/services/llm_tools_service.rb`)
Defines available tools that the LLM can call:
- `navigate_to_page` - Navigate to app pages with optional filters
- `list_users` - Get users in organization with filtering
- `list_teams` - Get teams with filtering
- `list_organizations` - Get organizations accessible by user
- `list_lists` - Get lists with filtering
- `search` - Cross-resource search
- `create_user` - Create new user and send invitation
- `create_team` - Create new team
- `create_list` - Create new list
- `update_user` - Update user info or role/status
- `update_team` - Update team info
- `suspend_user` - Suspend or unsuspend user

Each tool includes:
- Detailed description
- Parameter schema with types and validation
- Usage examples in description

#### 4. **LLMToolExecutorService** (`app/services/llm_tool_executor_service.rb`)
Executes tool calls from the LLM:
- Validates user has required permissions (Pundit)
- Executes database queries or operations
- Returns formatted results
- Handles errors gracefully

**Tool Execution Flow:**
1. LLM decides to call a tool
2. Tool call is extracted from LLM response
3. Executor validates authorization
4. Executes the tool operation
5. Formats result for LLM and frontend
6. Returns formatted message

#### 5. **ChatContext** (`app/models/chat_context.rb`)
Provides context-aware information:
- Current location (dashboard, floating, list_detail, etc.)
- User and organization information
- Focused resource (List, Team, Organization)
- System prompt generation
- Available suggestions based on context

### Message Flow

```
User Message
    ↓
ChatsController#create_message
    ↓
ChatCompletionService
    ├─ ChatRoutingService → Check for navigation intent
    │  └─ If navigation → Create navigation message
    │
    ├─ LLMToolsService → Build available tools
    │
    ├─ call_llm_with_tools(RubyLLM)
    │  └─ Add system prompt with tool descriptions
    │  └─ Add message history
    │  └─ Call LLM with tools
    │
    ├─ Check if LLM returned tool calls
    │  ├─ If tool call → LLMToolExecutorService
    │  │  └─ Execute tool (list, create, update, etc.)
    │  │  └─ Format result as message
    │  │
    │  └─ If text response → Create assistant message
    │
    └─ Create Message record
       └─ Render via Turbo Stream
          └─ Frontend detects message type
             ├─ Navigation → ChatNavigationController → Turbo.visit()
             ├─ Tool result → Display formatted results
             └─ Text → Show markdown response
```

## Message Types

### 1. Navigation Messages
Created when user intent matches existing app page.

**Template:** `app/views/message_templates/_navigation.html.erb`

**Structure:**
```erb
{
  template_type: "navigation",
  content: "Navigating to Show all users...",
  metadata: {
    navigation: {
      path: "/admin/users",
      filters: { status: "active" }
    }
  }
}
```

**Frontend Handling:** ChatNavigationController detects and redirects using Turbo.visit()

### 2. Tool Result Messages
Created when LLM calls a tool (list_users, create_team, etc.)

**Templates:**
- `_list.html.erb` - For list operations (users, teams, organizations, lists)
- `_resource.html.erb` - For create/update operations
- `_search_results.html.erb` - For search results

**Structure:**
```erb
{
  template_type: "list" | "resource" | "search_results",
  content: "Found 10 active users",
  metadata: {
    tool_call: "list_users",
    tool_result: {
      type: "list",
      resource_type: "User",
      total_count: 10,
      items: [...]
    }
  }
}
```

### 3. Regular Messages
Standard chat responses from the LLM.

**Structure:**
```erb
{
  role: "assistant",
  content: "I can help you manage users. Use /browse to see all lists or /search to find something specific.",
  template_type: nil
}
```

## Frontend Components

### ChatNavigationController (`app/javascript/controllers/chat_navigation_controller.js`)
Stimulus controller that:
- Observes chat messages container for new messages
- Detects navigation and tool result markers
- Handles page navigation via Turbo.visit()
- Logs tool results for debugging

**Key Methods:**
- `connect()` - Set up observer when controller initializes
- `checkForNavigationMessage()` - Check if message is navigation
- `navigate()` - Perform page navigation with filters
- `handleToolResult()` - Process tool results

## Usage Examples

### 1. Navigate to Users Page
**User:** "Show me active users"

**Flow:**
1. ChatRoutingService detects "active users" intent
2. Returns routing data: `{ action: :navigate, path: :admin_users }`
3. Creates navigation message with filters
4. Frontend navigates to `/admin/users?status=active`

### 2. Create New User
**User:** "Create a new user with email john@example.com named John Smith"

**Flow:**
1. ChatRoutingService finds no navigation match
2. LLM receives available tools
3. LLM calls `create_user` tool with parameters
4. LLMToolExecutorService creates user and sends invitation
5. Returns user details as formatted message
6. Frontend displays success message with user info

### 3. List Teams with Filter
**User:** "Show me all teams in this organization"

**Flow:**
1. LLM calls `list_teams` tool
2. Executor queries current organization teams
3. Returns formatted list with team count
4. Frontend displays paginated results

### 4. Search for Lists
**User:** "Search for lists about budget"

**Flow:**
1. LLM calls `search` tool with query "budget"
2. SearchService returns matching lists
3. Executor formats results
4. Frontend displays search results with links

## Authorization & Security

### Pundit Integration
All tool executions check authorization:
```ruby
authorize(:admin_user, :read?)   # For listing users
authorize(:team, :create?)        # For creating teams
authorize(@list, :edit?)          # For updating lists
```

### Org Boundary Validation
All queries scope to current organization:
```ruby
@organization.users
@organization.lists
policy_scope(List)  # Scoped by Pundit
```

### Input Validation
LLM tools validate:
- Email format
- Required fields
- Resource existence
- User permissions

### Prompt Injection Detection
Existing `PromptInjectionDetector` checks message content before processing.

### Content Moderation
Existing `ContentModerationService` (OpenAI) checks for policy violations.

## Configuration

### Default LLM Model
Set in `ChatCompletionService#default_model`:
```ruby
def default_model
  "gpt-4o-mini"  # Can be configured per org/user
end
```

### System Prompt
Enhanced in `ChatCompletionService#enhanced_system_prompt`:
- Base prompt from ChatContext
- Tool instruction guidance
- Feature explanations

### Tool Availability
Tools are built dynamically in `LLMToolsService#build_tools` based on:
- User permissions
- Organization context
- Available features

## Testing Scenarios

### 1. Navigation Intent Detection
```ruby
# Test ChatRoutingService with various user messages
service = ChatRoutingService.new(
  user_message: @message,
  chat: @chat,
  user: @user,
  organization: @organization
)
result = service.call
assert result.data[:action] == :navigate
assert result.data[:path] == :admin_users
```

### 2. Tool Execution
```ruby
# Test LLMToolExecutorService
executor = LLMToolExecutorService.new(
  tool_name: "list_users",
  tool_input: { query: "john", status: "active" },
  user: @user,
  organization: @organization,
  chat_context: @context
)
result = executor.call
assert result.success?
assert result.data[:total_count] > 0
```

### 3. End-to-End Chat Flow
```ruby
# Send message to chat
post create_message_chat_path(@chat), params: {
  message: { content: "Show me active users" }
}

# Verify navigation message created
assert @chat.messages.last.template_type == "navigation"
assert @chat.messages.last.metadata["navigation"]["path"] == "/admin/users"
```

## Troubleshooting

### LLM Tool Calls Not Working
1. Check if tools are being passed to RubyLLM
2. Verify LLM model supports tool calling (GPT-4, Claude 3+, etc.)
3. Check LLMToolsService returns non-empty tools array
4. Review RubyLLM response format extraction

### Navigation Not Working
1. Verify ChatNavigationController is registered in controllers/index.js
2. Check browser console for JavaScript errors
3. Ensure navigation message has correct metadata structure
4. Test Turbo.visit() manually in browser console

### Tool Execution Failing
1. Check user authorization (Pundit policies)
2. Verify organization scoping
3. Review error logs in `Rails.logger`
4. Test tool executor service directly in Rails console

### Message Not Appearing
1. Check Turbo Stream response format
2. Verify message template exists
3. Check chat_messages container has correct ID
4. Verify unified-chat controller is connected

## Future Enhancements

1. **Conversational Context:** Store conversation state for multi-turn operations
2. **Tool Chaining:** Enable LLM to call multiple tools in sequence
3. **Custom Tools:** Allow organizations to define custom tools
4. **Analytics:** Track which tools are used most frequently
5. **Tool History:** Show user what the LLM has done
6. **Confirmations:** Ask user to confirm before executing certain operations
7. **Batch Operations:** Support bulk user/team operations via chat
8. **RAG Integration:** Combine with document search for context

## API Reference

### ChatCompletionService
```ruby
service = ChatCompletionService.new(chat, user_message, context)
result = service.call
# Returns: { success: true, data: Message }
```

### ChatRoutingService
```ruby
service = ChatRoutingService.new(user_message:, chat:, user:, organization:)
result = service.call
# Returns: { success: true, data: { action, path, filters } }
```

### LLMToolsService
```ruby
service = LLMToolsService.new(user:, organization:, chat_context:)
result = service.call
# Returns: { success: true, data: [tools_array] }
```

### LLMToolExecutorService
```ruby
executor = LLMToolExecutorService.new(
  tool_name:,
  tool_input:,
  user:,
  organization:,
  chat_context:
)
result = executor.call
# Returns: { success: true, data: {type, items, total_count, ...} }
```

## Files Modified/Created

### New Files
- `app/services/chat_routing_service.rb`
- `app/services/llm_tools_service.rb`
- `app/services/llm_tool_executor_service.rb`
- `app/javascript/controllers/chat_navigation_controller.js`
- `app/views/message_templates/_navigation.html.erb`
- `app/views/message_templates/_list.html.erb`
- `app/views/message_templates/_resource.html.erb`

### Modified Files
- `app/services/chat_completion_service.rb` - Added tool support and routing
- `app/views/chat/_unified_chat.html.erb` - Added chat-navigation controller
- `app/javascript/controllers/index.js` - Registered chat-navigation controller

## Integration Points

The chat system integrates with:
- **Pundit** - Authorization checks via policies
- **RubyLLM** - LLM provider abstraction
- **SearchService** - Cross-resource search
- **User/Organization/Team models** - Data queries
- **Turbo/Stimulus** - Frontend interactions
- **Security services** - Prompt injection & content moderation

## Performance Considerations

1. **Message History Limit:** Last 20 messages for context (configurable)
2. **Tool Response Caching:** Tool results cached in message metadata
3. **Pagination:** List tools paginate results (20 per page)
4. **Authorization:** Pundit caches policy instances
5. **LLM Calls:** Tool calls reduce reliance on LLM text generation

## Notes

- All chat operations require user authentication
- Organization scoping is enforced at all levels
- Tool calls respect existing Pundit policies
- Navigation messages don't require LLM processing
- Message history is preserved in database for training/debugging
