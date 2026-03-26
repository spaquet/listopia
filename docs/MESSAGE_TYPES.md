# Message Types in Listopia Chat

Complete reference of all message types that can be displayed in the unified chat interface. Each type represents a distinct interaction pattern, visual presentation, and payload structure.

**Status:** Architecture Document | **Last Updated:** 2026-03-25

---

## Quick Reference

| Type | When | Payload | Component | User Action |
|------|------|---------|-----------|-------------|
| **text** | General responses, answers, explanations | `content: String` | Markdown renderer | Read/copy |
| **planning_form** | Complex request detected, needs clarification | `questions: Array, form_id: String` | Question form | Fill & submit |
| **list_created** | List successfully created | `list_id, title, item_count, structure` | Confirmation card | View/explore |
| **progress_indicator** | Processing (generating items, analyzing) | `status, message, step_count, current_step` | Spinner + status | Wait |
| **agent_running** | Agent actively executing | `agent_id, run_id, steps, tokens_used, status` | Real-time log | Monitor/cancel |
| **agent_paused** | Agent awaiting user input (HITL) | `question, options, run_id, interaction_id` | Modal/buttons | Choose option |
| **navigation** | Route to a page | `path, target, new_window` | Meta tag | Auto-navigate |
| **search_results** | Search query executed | `results: Array, count, query, took_ms` | Results table/cards | Click result |
| **resource_created** | User/team/org created | `resource_type, id, name, next_steps` | Confirmation card | View resource |
| **error** | Operation failed | `error_code, message, suggestion, retry_info` | Error banner | Retry/report |
| **command_response** | Command executed (/search, /help) | `content, results_count, execution_time` | Formatted response | Use results |
| **team_summary** | Team stats/status | `team_id, member_count, activity_summary` | Summary card | Drill down |

---

## Detailed Message Type Reference

### 1. Text Message

**Purpose:** General conversational response, explanations, help content, general questions answered

**When Shown:**
- Answering "How do I...?" questions
- Explaining features or functionality
- General Q&A with tools
- Following up after operations

**Payload Structure:**

```ruby
{
  type: "text",
  role: "assistant",
  content: "String with markdown",
  metadata: {
    model_used: "gpt-5-mini",
    tokens_used: 342,
    tool_calls: [],
    processing_time_ms: 2340
  }
}
```

**Frontend Component:**
```erb
<div class="message-text">
  <%= simple_format(@message.content) %>
  <!-- Renders markdown: bold, lists, links, code blocks -->
</div>
```

**Example:**
```
User: "How do I add people to my team?"

Response:
You can add team members by:
1. Open your team
2. Click "Invite member"
3. Enter their email address
4. They'll receive an invitation via magic link

Members can have different roles: Admin, Contributor, Viewer
```

---

### 2. Planning Form

**Purpose:** Collect clarifying information for complex requests before creating resources

**When Shown:**
- Complex list creation detected (multi-location, time-bound, hierarchical)
- Pre-run questions configured on an agent
- Resource creation needs parameters

**Trigger:**
- `CombinedIntentComplexityService` detects `is_complex: true`
- OR Agent has `pre_run_questions` configured

**Payload Structure:**

```ruby
{
  type: "planning_form",
  form_id: "uuid",
  title: "Plan your roadshow",
  description: "Help me understand your needs",
  questions: [
    {
      key: "locations",
      question: "Which cities will you visit?",
      type: "text",  # text, textarea, select, checkbox, date
      required: true,
      placeholder: "e.g., NYC, LA, Chicago"
    },
    {
      key: "budget",
      question: "What's your budget? (optional)",
      type: "text",
      required: false,
      placeholder: "e.g., $50,000"
    },
    {
      key: "timeline",
      question: "When do you need this?",
      type: "date",
      required: true
    }
  ],
  metadata: {
    planning_domain: "event",
    complexity_level: "high",
    category: "professional"
  }
}
```

**Frontend Component:**
```erb
<form id="<%= @message.form_id %>" class="planning-form">
  <% @message.questions.each do |q| %>
    <div class="form-group">
      <label><%= q[:question] %></label>
      <%= render_input_field(q) %>
    </div>
  <% end %>
  <button type="submit">Continue →</button>
</form>
```

**User Flow:**
1. Form displayed to user
2. User fills answers
3. On submit: POST `/chats/:id/answer_planning_form`
4. Answers stored in agent pre_run_answers
5. Agent resumes with answers
6. Processing continues

**Example:**
```
Form Title: Plan your summer retreat

Q: Which cities will you visit?
A: Sonoma, Napa Valley, San Francisco

Q: What's your budget?
A: $5000 per person

Q: When do you need this?
A: July 15-17, 2026

[Continue →]
```

---

### 3. List Created

**Purpose:** Confirm successful list creation with summary and next actions

**When Shown:**
- List created successfully (simple or complex)
- Pre-creation planning complete
- Items generated and saved

**Payload Structure:**

```ruby
{
  type: "list_created",
  list_id: "uuid",
  title: "US Roadshow Planning",
  description: "5-city tour with logistics and coordination",
  item_count: 28,
  structure: {
    parent_items: 5,
    sublists: 5,
    subdivision_type: "locations",  # locations, phases, teams, books, modules
    hierarchy: {
      "New York" => 6,
      "Chicago" => 5,
      "Boston" => 4,
      "Denver" => 4,
      "Seattle" => 4
    }
  },
  metadata: {
    created_by_agent: "ListCreationAgent",
    agent_run_id: "uuid",
    planning_domain: "event",
    creation_time_ms: 15200
  }
}
```

**Frontend Component:**
```erb
<div class="message-list-created">
  <div class="success-header">
    ✅ List created: <%= @message.title %>
  </div>

  <div class="list-summary">
    <p><%= @message.description %></p>

    <div class="structure-summary">
      <strong><%= @message.item_count %> total items</strong>
      <ul>
        <% @message.structure[:hierarchy].each do |name, count| %>
          <li><%= name %>: <%= count %> items</li>
        <% end %>
      </ul>
    </div>
  </div>

  <div class="action-buttons">
    <%= link_to "View in full list", list_path(@message.list_id), class: "btn btn-primary" %>
    <%= link_to "Refine items", edit_list_path(@message.list_id), class: "btn btn-secondary" %>
  </div>
</div>
```

**Example:**
```
✅ List created: US Roadshow Planning

New York: 6 items
Chicago: 5 items
Boston: 4 items
Denver: 4 items
Seattle: 4 items

Total: 28 items across 5 locations

[View in full list] [Refine items]
```

---

### 4. Progress Indicator

**Purpose:** Real-time visual feedback during background processing (generating items, analyzing requests)

**When Shown:**
- Generating items for sublists (ItemGenerationService running)
- Analyzing request complexity
- Creating list structure
- Any background processing that takes >1 second

**Payload Structure:**

```ruby
{
  type: "progress_indicator",
  status: "processing",  # processing, analyzing, generating, creating
  message: "Generating items for New York...",
  progress: {
    current_step: 2,
    total_steps: 5,
    percentage: 40
  },
  metadata: {
    operation: "item_generation",
    subdivision: "New York",
    started_at: Time.current
  }
}
```

**Frontend Component:**
```erb
<div class="message-progress">
  <div class="progress-spinner"></div>
  <p><%= @message.message %></p>

  <% if @message.progress %>
    <div class="progress-bar">
      <div class="progress-fill" style="width: <%= @message.progress[:percentage] %>%"></div>
    </div>
    <small>
      Step <%= @message.progress[:current_step] %> of <%= @message.progress[:total_steps] %>
    </small>
  <% end %>
</div>

<script>
  // Auto-update via Turbo Stream or WebSocket
  // When complete, replace with next message type
</script>
```

**Real-Time Updates via Turbo Streams:**

```ruby
# In ItemGenerationService or background job
broadcast_replace_to(
  "chat_#{chat.id}",
  target: "message_#{message.id}",
  partial: "message_templates/progress_indicator",
  locals: { progress: 40, step: 2, message: "Generating items for NYC..." }
)
```

**Example Sequence:**
```
1. Generating items for New York... (10%)
2. Generating items for Chicago... (30%)
3. Generating items for Boston... (50%)
4. Creating list structure... (80%)
5. Saving to database... (100%)
```

---

### 5. Agent Running

**Purpose:** Show agent in real-time execution with step-by-step progress and token usage

**When Shown:**
- Agent actively executing (not paused)
- User requested manual agent run
- Auto-triggered agent is executing
- User is monitoring agent progress

**Payload Structure:**

```ruby
{
  type: "agent_running",
  agent_id: "uuid",
  agent_name: "Task Breakdown Agent",
  run_id: "uuid",
  status: "running",  # running, awaiting_input, completed, failed
  steps: [
    {
      number: 1,
      name: "Analyzing goal",
      status: "completed",
      duration_ms: 1200,
      timestamp: Time.current
    },
    {
      number: 2,
      name: "Identifying phases",
      status: "in_progress",
      duration_ms: 0,
      timestamp: Time.current
    }
  ],
  token_usage: {
    input_tokens: 1500,
    output_tokens: 450,
    total_tokens: 1950,
    remaining_budget: 2050
  },
  metadata: {
    timeout_seconds: 120,
    max_steps: 20,
    model: "gpt-4o-mini"
  }
}
```

**Frontend Component:**
```erb
<div class="message-agent-running">
  <div class="agent-header">
    🤖 <%= @message.agent_name %> (Run #<%= @message.run_id %>)
  </div>

  <div class="steps-timeline">
    <% @message.steps.each do |step| %>
      <div class="step" data-status="<%= step[:status] %>">
        <span class="step-number"><%= step[:number] %></span>
        <span class="step-name"><%= step[:name] %></span>

        <% if step[:status] == "completed" %>
          <span class="step-status">✓ (<%= step[:duration_ms] %>ms)</span>
        <% elsif step[:status] == "in_progress" %>
          <span class="step-status">⏳ running...</span>
        <% else %>
          <span class="step-status">⏸</span>
        <% end %>
      </div>
    <% end %>
  </div>

  <div class="token-usage">
    Tokens: <%= @message.token_usage[:total_tokens] %> /
    <%= @message.token_usage[:total_tokens] + @message.token_usage[:remaining_budget] %>
  </div>

  <div class="agent-controls">
    <%= button_to "Pause", agent_run_pause_path(@message.run_id), method: :post %>
    <%= button_to "Cancel", agent_run_cancel_path(@message.run_id), method: :post %>
  </div>
</div>

<script>
  // WebSocket or Turbo Stream updates
  // Replaces this message with updated version
</script>
```

**Update Flow:**
- Agent emits step_completed event
- Backend broadcasts updated message via Turbo Stream
- Frontend replaces old message with new progress
- Loop until agent completes or fails

**Example:**
```
🤖 Task Breakdown Agent (Run #abc-123)

Steps:
  ✓ Understanding goal (450ms)
  ✓ Identifying phases (1200ms)
  ⏳ Breaking into tasks (running...)
  ⏸ Assigning priorities
  ⏸ Requesting confirmation

Tokens: 1,950 / 4,000
```

---

### 6. Agent Paused (Human-in-the-Loop)

**Purpose:** Request user input or confirmation while agent is executing

**When Shown:**
- Agent calls `ask_user()` tool
- Agent calls `confirm_action()` tool
- Agent needs clarification to proceed
- Destructive operation needs approval

**Payload Structure:**

```ruby
{
  type: "agent_paused",
  agent_id: "uuid",
  agent_name: "List Organizer",
  run_id: "uuid",
  interaction_id: "uuid",
  question: "I found 3 potential duplicate items. What should I do?",
  interaction_type: "ask_user",  # ask_user or confirm_action
  options: [
    {
      value: "delete",
      label: "Yes, delete them",
      description: nil
    },
    {
      value: "keep",
      label: "No, keep them",
      description: nil
    },
    {
      value: "review",
      label: "Review first",
      description: "Show me the items before deciding"
    }
  ],
  metadata: {
    context: "Detected duplicates during reorganization",
    items_affected: 3
  }
}
```

**Frontend Component:**
```erb
<div class="message-agent-paused">
  <div class="paused-banner">
    🤖 <%= @message.agent_name %> is waiting for your input
  </div>

  <div class="question-box">
    <p><%= @message.question %></p>
  </div>

  <div class="action-buttons">
    <% @message.options.each do |option| %>
      <button
        data-interaction-id="<%= @message.interaction_id %>"
        data-value="<%= option[:value] %>"
        class="btn-agent-response"
      >
        <%= option[:label] %>
        <% if option[:description] %>
          <small><%= option[:description] %></small>
        <% end %>
      </button>
    <% end %>
  </div>
</div>

<script>
  document.querySelectorAll('.btn-agent-response').forEach(btn => {
    btn.addEventListener('click', () => {
      const interactionId = btn.dataset.interactionId;
      const value = btn.dataset.value;

      // POST to /agent_runs/:id/respond_to_interaction
      fetch(`/agent_runs/${interactionId}/respond`, {
        method: 'POST',
        body: JSON.stringify({ response: value })
      });
    });
  });
</script>
```

**Flow:**
1. Agent calls ask_user/confirm_action tool
2. AiAgentInteraction created
3. Run status → paused
4. Message type: agent_paused broadcasted to chat
5. User clicks option
6. Response saved to interaction
7. AgentRunJob resumes with answer
8. Agent continues execution

**Example: Confirmation**
```
🤖 List Organizer is waiting for your input

I'm about to re-prioritize 12 items.
This will move 8 to 'High' and 4 to 'Low'.
Do you approve?

[Confirm] [Cancel] [Review Changes]
```

---

### 7. Navigation

**Purpose:** Route user to a different page without text response

**When Shown:**
- User asks to navigate ("Show users list")
- Intent detected as navigation
- Page transition needed

**Payload Structure:**

```ruby
{
  type: "navigation",
  path: "/admin/users",
  target: "_self",  # _self or _blank
  label: "Navigating to users list...",
  metadata: {
    trigger_agent: "NavigationAgent",
    page_title: "Users"
  }
}
```

**Frontend Component:**
```erb
<div class="message-navigation" data-navigation-path="<%= @message.path %>">
  <p><%= @message.label %></p>
</div>

<script>
  document.addEventListener('turbo:load', () => {
    const navMsg = document.querySelector('[data-navigation-path]');
    if (navMsg) {
      const path = navMsg.dataset.navigationPath;
      Turbo.visit(path);
    }
  });
</script>
```

**Example:**
```
User: "Show me the users list"
Response:
Navigating to users list...
[Auto-navigates to /admin/users]
```

---

### 8. Search Results

**Purpose:** Display results from a search query (lists, items, tags)

**When Shown:**
- `/search` command executed
- Intent detected as search_data
- Search query processed

**Payload Structure:**

```ruby
{
  type: "search_results",
  query: "budget",
  result_count: 3,
  results: [
    {
      type: "list",
      id: "uuid",
      title: "Budget 2026",
      description: "Annual budget planning",
      item_count: 12,
      organization: "Acme Corp"
    },
    {
      type: "list",
      id: "uuid",
      title: "Project Budget",
      description: "Website redesign budget",
      item_count: 8,
      organization: "Acme Corp"
    },
    {
      type: "list",
      id: "uuid",
      title: "Travel Budget",
      description: "Q2 travel expenses",
      item_count: 5,
      organization: "Acme Corp"
    }
  ],
  metadata: {
    search_time_ms: 125,
    scope: "lists"
  }
}
```

**Frontend Component:**
```erb
<div class="message-search-results">
  <p>Found <%= @message.result_count %> results for "<%= @message.query %>"</p>

  <div class="results-list">
    <% @message.results.each do |result| %>
      <div class="result-item">
        <h4><%= link_to result[:title], list_path(result[:id]) %></h4>
        <p class="result-description"><%= result[:description] %></p>
        <small><%= result[:item_count] %> items</small>
      </div>
    <% end %>
  </div>
</div>
```

**Example:**
```
Found 3 results for "budget"

📋 Budget 2026
   Annual budget planning
   12 items

📋 Project Budget
   Website redesign budget
   8 items

📋 Travel Budget
   Q2 travel expenses
   5 items
```

---

### 9. Resource Created

**Purpose:** Confirm successful creation of user, team, or organization

**When Shown:**
- User created via chat
- Team created via chat
- Organization created via chat

**Payload Structure:**

```ruby
{
  type: "resource_created",
  resource_type: "user",  # user, team, organization
  resource_id: "uuid",
  resource_name: "john@example.com",
  display_name: "John Smith",
  metadata: {
    action: "created",
    next_step: "invite_sent",
    invitation_link: "https://...",
    created_by_agent: "ResourceCreationAgent"
  }
}
```

**Frontend Component:**
```erb
<div class="message-resource-created">
  <div class="success-header">
    ✅ <%= @message.resource_type.titleize %> created
  </div>

  <div class="resource-details">
    <strong><%= @message.display_name %></strong>
    <p><%= @message.resource_name %></p>
  </div>

  <div class="next-steps">
    <% if @message.metadata[:next_step] == "invite_sent" %>
      <p>Invitation email sent. They can join using the magic link.</p>
    <% end %>
  </div>

  <div class="action-buttons">
    <%= link_to "View #{@message.resource_type}",
        resource_path(@message.resource_type, @message.resource_id),
        class: "btn btn-primary" %>
  </div>
</div>
```

**Example:**
```
✅ User created

John Smith
john@example.com

Invitation email sent. They can join using the magic link.

[View user]
```

---

### 10. Error Message

**Purpose:** Report operation failure with helpful guidance

**When Shown:**
- Operation failed
- Validation error
- API error
- Resource not found
- Permission denied

**Payload Structure:**

```ruby
{
  type: "error",
  error_code: "DUPLICATE_EMAIL",
  message: "A user with this email already exists.",
  suggestion: "Try a different email or contact the user if they need account recovery.",
  retry_option: true,
  metadata: {
    timestamp: Time.current,
    user_action: "create_user",
    severity: "warning"  # warning, error, critical
  }
}
```

**Frontend Component:**
```erb
<div class="message-error">
  <div class="error-banner">
    ❌ <%= @message.message %>
  </div>

  <% if @message.suggestion %>
    <p class="error-suggestion">
      💡 <%= @message.suggestion %>
    </p>
  <% end %>

  <% if @message.retry_option %>
    <button class="btn btn-secondary">Try Again</button>
  <% end %>
</div>
```

**Example:**
```
❌ A user with this email already exists.

💡 Try a different email or contact the user if they need account recovery.

[Try Again]
```

---

### 11. Command Response

**Purpose:** Result of a slash command (synchronous execution)

**When Shown:**
- `/search` command executed
- `/help` command executed
- `/browse` command executed
- Command-based operations

**Payload Structure:**

```ruby
{
  type: "command_response",
  command: "search",
  content: "String with results",
  results_count: 5,
  execution_time_ms: 145,
  metadata: {
    scope: "lists",
    filters_applied: ["status:active"]
  }
}
```

**Frontend Component:**
```erb
<div class="message-command-response">
  <div class="response-content">
    <%= simple_format(@message.content) %>
  </div>

  <small class="response-timing">
    Found <%= @message.results_count %> results in <%= @message.execution_time_ms %>ms
  </small>
</div>
```

---

### 12. Team Summary

**Purpose:** Display team statistics and activity overview

**When Shown:**
- User asks for team status
- Admin requests team summary
- Analytics/reporting context

**Payload Structure:**

```ruby
{
  type: "team_summary",
  team_id: "uuid",
  team_name: "Engineering",
  member_count: 8,
  activity: {
    items_completed_this_week: 24,
    lists_active: 5,
    members_active: 7
  },
  metadata: {
    generated_by_agent: "StatusReportAgent",
    generated_at: Time.current
  }
}
```

**Example:**
```
📊 Engineering Team Summary

8 members
5 active lists
24 items completed this week
7 members active

[View team details]
```

---

## Message Type Selection Logic

**In the Chat System:**

```ruby
# After agent execution or service processing
def determine_message_type(result)
  case result
  when result.type == :list_created
    "list_created"
  when result.has_questions?
    "planning_form"
  when result.type == :navigation
    "navigation"
  when result.type == :search
    "search_results"
  when result.error?
    "error"
  when result.type == :resource_created
    "resource_created"
  else
    "text"  # Default fallback
  end
end
```

---

## Message Type Flow by Request Type

### Simple List Creation
```
User: "Create grocery list"
  ↓ CombinedIntentComplexityService detects: is_complex=false
  ↓ ListCreationAgent executes
  → Message type: list_created
```

### Complex List Creation
```
User: "Plan US roadshow"
  ↓ CombinedIntentComplexityService detects: is_complex=true
  ↓ ListCreationAgent invoked
  → Message type: planning_form (show questions)
  ↓ User answers
  ↓ Agent processes answers, generates items
  → Message type: progress_indicator (generating items)
  → Message type: list_created (success)
```

### Navigation
```
User: "Show users"
  ↓ CombinedIntentComplexityService detects: intent=navigate
  ↓ NavigationAgent
  → Message type: navigation
```

### Search
```
User: "/search budget"
  ↓ ChatsController detects "/" command
  ↓ SearchAgent executes
  → Message type: search_results
```

### Agent with HITL
```
Agent executing...
  ↓ Agent calls ask_user() tool
  → Message type: agent_paused
  ↓ User responds
  ↓ Agent resumes
  → Message type: agent_running (continues) or final result
```

---

## Database Schema

Messages are stored with `type` column:

```ruby
create_table :messages, id: :uuid do |t|
  t.uuid :chat_id, null: false
  t.uuid :user_id
  t.string :role  # user, assistant, system
  t.text :content
  t.string :type  # text, list_created, planning_form, etc.
  t.jsonb :data  # Payload structure specific to type
  t.jsonb :metadata
  t.timestamps

  t.index [:chat_id, :type]
  t.index [:type]
end
```

**Example Record:**
```ruby
Message.create(
  chat_id: chat.id,
  role: "assistant",
  type: "planning_form",
  data: {
    form_id: "uuid",
    questions: [...]
  },
  metadata: {
    planning_domain: "event",
    complexity: "high"
  }
)
```

---

## Frontend Rendering

**View Component Pattern:**

```erb
<!-- app/views/message_templates/_message.html.erb -->

<div class="message message-<%= @message.type %>" data-type="<%= @message.type %>">
  <%= render "message_templates/#{@message.type}", message: @message %>
</div>
```

**Each Type Has Its Own Partial:**
- `message_templates/_text.html.erb`
- `message_templates/_planning_form.html.erb`
- `message_templates/_list_created.html.erb`
- `message_templates/_progress_indicator.html.erb`
- etc.

---

## Testing

### Unit Test Example

```ruby
describe "Message Types" do
  it "renders text message" do
    message = Message.create(type: "text", content: "Hello")
    expect(render_message(message)).to include("Hello")
  end

  it "renders planning form with questions" do
    message = Message.create(
      type: "planning_form",
      data: { questions: [...] }
    )
    expect(render_message(message)).to have_form_fields
  end

  it "renders list_created with summary" do
    message = Message.create(
      type: "list_created",
      data: { list_id: list.id, item_count: 28 }
    )
    expect(render_message(message)).to include("28 items")
  end
end
```

---

## Key Design Principles

1. **Type First**: Message type determines rendering, not content
2. **Payload Agnostic**: Each type carries only necessary data
3. **Turbo Streams Compatible**: All types support real-time updates
4. **Fallback Safe**: Missing data renders gracefully
5. **Agent-Oriented**: Types align with agent response patterns

---

**Last Updated:** 2026-03-25
**Related:** [AGENTS.md](./AGENTS.md), [CHAT_FLOW.md](./CHAT_FLOW.md), [CHAT_REQUEST_TYPES.md](./CHAT_REQUEST_TYPES.md)
