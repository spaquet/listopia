# Listopia AI Agents - Complete Reference

**Version 2.0** — Full redesign with structured instructions, pre-run questions, event-driven triggers, embeddings, and human-in-the-loop support.

---

## Overview

**AI Agents** are autonomous LLM-powered workers that help users manage lists and tasks. They're configured with clear instructions and can be triggered manually, by events, or on a schedule. Agents can ask clarifying questions before running, pause to request user confirmation mid-execution, and maintain long-term memory through semantic embeddings.

**What Agents Can Do:**
- Break down complex goals into actionable task lists
- Generate executive status reports across all lists
- Reorganize lists based on priority and relationships
- Research and enrich items with external information
- Run on a schedule (e.g., weekly reports)
- Trigger automatically when events occur (e.g., item completed)
- Request human approval before taking significant actions
- Learn about user preferences through embeddings

---

## Agent Configuration (5 Key Fields)

Every agent is defined by these core fields:

### 1. **Persona** (formerly `prompt`)
Who the agent is — its role, tone, and constraints. Example:
> "You are a senior project manager expert at decomposing complex goals into clear, achievable tasks. Your role is to understand the user's goal, identify major phases, create specific tasks, assign realistic priorities."

### 2. **Instructions**
Step-by-step SOP — what the agent actually does, in order. Example:
```
1. Understand the goal (ask clarifying questions if needed)
2. Identify major phases and milestones
3. Break into specific, actionable tasks
4. Assign priority and effort estimate to each
5. Ask user to confirm before creating items
```

### 3. **Body Context Config** (JSONB)
What context to auto-load before execution:
- `{ "load": "invocable" }` — loads the target list/item the agent is working on
- `{ "load": "all_lists" }` — loads all org lists (for status reports)
- `{ "load": "recent_runs", "limit": 5 }` — loads recent agent run summaries (cross-run memory)

The LLM receives this context automatically in the system prompt.

### 4. **Pre-Run Questions** (JSONB array)
Questions asked to the user BEFORE execution starts. User enters answers, which are injected into the task parameters:
```json
[
  {
    "key": "goal",
    "question": "What is the main goal you want to accomplish?",
    "required": true
  },
  {
    "key": "deadline",
    "question": "Do you have a deadline? (optional)",
    "required": false
  }
]
```

If `pre_run_questions` is present, the run enters `awaiting_input` state, displaying a form to the user. After answering, the job enqueues.

### 5. **Trigger Config** (JSONB)
How the agent is invoked:
- `{ "type": "manual" }` — User clicks "Run"
- `{ "type": "event", "event_type": "list_item.completed" }` — Triggers when app events fire
- `{ "type": "schedule", "cron": "0 9 * * 1" }` — Runs on a cron schedule (Monday 9am)

---

## RubyLLM Integration

**RubyLLM** (v1.11+) is the gem powering all LLM interactions. It provides:
- OpenAI API interface
- Tool/function calling support
- Message history management
- Token usage tracking
- Streaming support

### Key RubyLLM Methods

```ruby
# Create chat instance
chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4o")

# Add messages to conversation history
chat.add_message(role: "system", content: "You are...")
chat.add_message(role: "user", content: "Create a list...")

# Register tools (function definitions)
chat.with_tool(CreateListTool)
chat.with_tool(UpdateItemTool)

# Execute LLM with registered tools
response = chat.complete

# Access message history
chat.messages.last           # Last message
chat.messages.last.tool_calls  # Tool invocations (Array<ToolCall>)

# Extract response components
response.content             # Text response
response.usage.input_tokens  # Token count
response.usage.output_tokens # Token count
```

### Tool Definition in RubyLLM

Tools are subclasses of `RubyLLM::Tool`:

```ruby
class CreateListTool < RubyLLM::Tool
  # Set tool description for LLM
  description "Create a new list with items"

  # Define parameters (appear in function schema)
  param :title, type: :string, desc: "List title", required: true
  param :items, type: :array, desc: "Items array", required: true

  # Tool name (used by LLM to invoke)
  def name
    "create_list"
  end

  # Called when LLM invokes this tool
  def execute(**kwargs)
    title = kwargs[:title]
    items = kwargs[:items]
    # ... create list and items ...
    { list_id: "...", items_created: 5 }
  end
end
```

---

## Run Lifecycle

```
Trigger (manual / event / schedule)
  ↓
AiAgentRun created (status: pending)
  ↓
IF pre_run_questions exist?
  ├─ run.status = awaiting_input
  ├─ User sees form with questions
  ├─ User answers → stored in run.pre_run_answers
  └─ AgentRunJob enqueued
  ↓
AgentExecutionService
  ├─ AgentContextBuilder: composes rich system prompt
  │   (persona + instructions + auto-loaded context + user answers)
  ├─ Create RubyLLM::Chat instance
  ├─ Add message history to chat
  ├─ Register tools with chat.with_tool()
  ├─ Call llm_chat.complete (RubyLLM handles OpenAI API)
  ├─ Extract tool_calls from response
  ├─ Tool execution loop:
  │   ├─ List CRUD (read, create, update, complete items)
  │   ├─ Web search
  │   ├─ Sub-agent invocation
  │   └─ HITL tools (ask_user, confirm_action)
  ├─ Add tool results back to message history
  ├─ IF ask_user/confirm_action tool:
  │   ├─ AiAgentInteraction created
  │   ├─ run.status = paused
  │   └─ Return (resume triggered by user answer)
  ├─ ELSE IF more tool calls needed:
  │   └─ Loop back to llm_chat.complete with updated messages
  └─ ELSE (agent complete):
      ├─ run.complete!
      ├─ Event.emit("agent_run.completed", ...)
      └─ Broadcast result to chat
```

---

## Message History & Tool Calling

### Message Structure

Agents maintain a message array in OpenAI format:

```ruby
messages = [
  {
    role: "system",
    content: "You are a list curator..."
  },
  {
    role: "user",
    content: "Create a list of 10 jets for world travel"
  },
  {
    role: "assistant",
    content: "I'll create a list of luxury jets...",
    tool_calls: [
      {
        id: "call_abc123",
        function: {
          name: "create_list",
          arguments: "{\"title\":\"10 Luxury Jets\",\"items\":[...]}"
        }
      }
    ]
  },
  {
    role: "tool",
    tool_call_id: "call_abc123",
    content: "{\"list_id\":\"uuid\",\"items_created\":10}"
  }
]
```

### Tool Call Extraction

After `llm_chat.complete`, RubyLLM provides tool calls:

```ruby
response = llm_chat.complete

# Extract content (text response)
content = response.content

# Extract tool calls from message history
if llm_chat.messages.last.respond_to?(:tool_calls)
  tool_calls = llm_chat.messages.last.tool_calls

  # Convert RubyLLM format to our format
  tool_calls.map do |tc|
    {
      id: tc.id || SecureRandom.uuid,
      function: {
        name: tc.name,                    # Tool name from RubyLLM
        arguments: tc.arguments.to_json   # Parameters as JSON
      }
    }
  end
end
```

### Feeding Results Back to LLM

After executing a tool, add the result to messages so LLM can see it:

```ruby
# Execute tool
result = AgentToolExecutorService.call(tool_call: tool_call, ...)

# Add result to message history
messages << {
  role: "tool",
  tool_call_id: tool_call["id"],
  content: result.data.to_json  # Must be JSON string
}

# Next llm_chat.complete call will see this result
# LLM decides: call more tools, or complete execution
```

---

## Memory System

### Short-Term (Within a Run)
- Message history (chat-like LLM loop)
- Shared state / tools results
- Tool outputs feed back to the LLM

### Long-Term (Across Runs)
**Cross-run context** via `body_context_config`:
- `{ "load": "recent_runs", "limit": 5 }` loads summaries of the last 5 completed runs
- Agent can learn from prior actions: "last time I checked, we had 23 high-priority items"

**Future:** Persistent user preferences, conversation history, and learned patterns.

### Embeddings
Agent embeddings are generated from `name + description + instructions` and enable:
- **Agent discovery** — Find relevant agents for a task via semantic search
- **Orchestration** — When a parent agent needs to delegate, it finds the best sub-agent via `AiAgent.find_for_task(task_description)`
- Reuses existing `EmbeddingGenerationService` and `pgvector` infrastructure

---

## Triggers: Manual, Event, Scheduled

### Manual Trigger
User clicks **"Run Agent"** in the UI.
```ruby
AgentTriggerService.trigger_manual(
  agent: agent,
  user: current_user,
  input: "Break down the roadshow planning",
  invocable: list
)
```

### Event-Triggered
Automatically invoke agents when app events fire. Subscriptions in `config/initializers/event_subscriptions.rb`:
```ruby
ActiveSupport::Notifications.subscribe("list_item.completed") do |_name, _start, _finish, _id, payload|
  AgentEventDispatchJob.perform_later("list_item.completed", payload)
end
```

**Example:** List Organizer agent triggers `on: "list_item.completed"` to reoptimize after item completion.

### Scheduled (Cron)
`AgentScheduleJob` runs every minute, evaluates cron expressions, and enqueues due agents.
```json
{ "type": "schedule", "cron": "0 9 * * 1" }
```
Runs every Monday at 9am. Standard cron syntax via `Fugit`.

---

## Human-in-the-Loop (HITL)

Agents can pause and request user input mid-execution via two HITL tools (always available):

### `ask_user(question, options[])`
Ask a free-form or multiple-choice question and wait for response.
```
Agent: "I found 5 potential duplicate items. Should I mark them for deletion?"
Options: ["Yes, delete them", "No, keep them", "Review first"]
```

### `confirm_action(description, expected_outcome)`
Request approval before taking a significant action.
```
Agent: "I'm about to re-prioritize 12 items. Do you approve?"
```

**Flow:**
1. Agent calls `ask_user` or `confirm_action` tool
2. `AiAgentToolExecutorService` creates an `AiAgentInteraction` record
3. Run status → `paused`
4. User sees a modal/form with the question
5. User answers → `AiAgentInteraction.mark_answered!`
6. Run resumes via `AgentRunJob` with the answer injected
7. LLM receives answer and continues execution

---

## Dynamic Tool Creation System

Since agents have different permissions, we **generate tool classes at runtime** using `AgentToolWrapper`:

```ruby
# In AgentExecutionService.make_llm_request()
tools = AgentToolBuilder.tools_for_agent(@agent)  # Get tools based on permissions

tools.each do |tool_hash|
  # Dynamically create a RubyLLM::Tool subclass
  tool_class = AgentToolWrapper.create_tool_class(
    tool_hash,                  # { name:, description:, parameters: }
    agent: @agent,              # Context for execution
    user: @user,
    organization: @organization,
    invocable: @run.invocable,
    run: @run
  )

  # Register with chat
  llm_chat.with_tool(tool_class)
end

# Each dynamic tool:
# - Has name, description, and param definitions from tool_hash
# - execute() method calls AgentToolExecutorService
# - Can access agent context (user, org, permissions)
```

### Why Dynamic?

1. **Permission filtering** — Only register tools the agent has permission to use
2. **Execution context** — Pass user/org/run context to tools
3. **Just-in-time generation** — No need to predefine 100 tool classes
4. **Consistency** — Single source of truth (TOOL_SPECS in AgentToolBuilder)

### Tool Parameter Schema

Tool parameters use OpenAI-compatible JSON Schema:

```ruby
# From TOOL_SPECS in AgentToolBuilder
{
  name: "create_list",
  description: "Create a new list with items",
  parameters: {
    type: "object",
    properties: {
      title: {
        type: "string",
        description: "List title",
        minLength: 1,
        maxLength: 255
      },
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            title: { type: "string" },
            description: { type: "string" },
            priority: { enum: ["low", "medium", "high"] }
          },
          required: ["title", "description"]  # ← Forces agent to provide both
        },
        minItems: 1
      }
    },
    required: ["title", "items"]
  }
}
```

**Key Design Decisions:**
- `required: ["title", "description"]` for items forces the LLM to provide both
- `minItems: 1` ensures at least one item
- `maxLength` prevents overly long titles
- `enum` restricts values (e.g., priority levels)

---

## Tools Available to Agents

### List & Item CRUD (gated by resources)
- `read_list` — get list details
- `read_list_items` — get items with filtering
- `create_list_item` — add new item
- `update_list_item` — modify item
- `complete_list_item` — mark done

### Integration Tools (gated by resources)
- `web_search` — search the web
- (Future: calendar, Slack, etc. via integrations)

### Agent Orchestration (gated by resources)
- `invoke_agent` — call another agent asynchronously
- `poll_agent_run` — check status of a sub-agent run

### Human-in-the-Loop (always available)
- `ask_user(question, options[])`
- `confirm_action(description, expected_outcome)`

**Permissions:** Each agent has `AiAgentResource` records defining what tools it can access. Example:
```
AiAgent "Task Breakdown"
├─ list (read_write)
├─ list_item (read_write)
└─ user_interaction (expect_response)
```

---

## Seeded Agents (4 System Agents)

### 1. **Task Breakdown Agent**
Decomposes goals into actionable tasks with priorities.
- **Persona:** Senior project manager
- **Trigger:** Manual
- **Pre-run questions:** Goal, deadline
- **Body context:** Invocable list (target list to fill)
- **Resources:** list (read_write), list_item (read_write), user_interaction
- **Cron:** N/A
- **Example:** "Break down the Q1 roadshow planning"

### 2. **Status Report Agent**
Generates weekly executive summaries.
- **Persona:** Executive assistant
- **Trigger:** Scheduled (Monday 9am)
- **Pre-run questions:** None (auto-runs)
- **Body context:** All lists in org
- **Resources:** list (read_only), list_item (read_only)
- **Cron:** `0 9 * * 1` (Monday 9am)
- **Example:** Automatically runs every Monday, sends summary

### 3. **List Organizer Agent**
Reoptimizes lists when items complete.
- **Persona:** GTD expert
- **Trigger:** Event-based (list_item.completed)
- **Pre-run questions:** None
- **Body context:** Invocable list
- **Resources:** list (read_write), list_item (read_write), user_interaction
- **Cron:** N/A
- **Example:** When an item is marked done, agent suggests reorganization

### 4. **Research Agent**
Enriches items with external information.
- **Persona:** Thorough researcher
- **Trigger:** Manual
- **Pre-run questions:** Research depth (quick / detailed)
- **Body context:** Invocable list
- **Resources:** list (read_write), list_item (read_write), web_search
- **Cron:** N/A
- **Example:** "Research all items in my reading list"

---

## Scopes & Access Control

Agents can be created at different scopes:
- **System agents** — Available to all users, managed by admins
- **Organization agents** — Scoped to a specific organization
- **Team agents** — Scoped to a team within an organization
- **User agents** — Personal agents for a single user

**Access:** `agent.accessible_by?(user)` determines if a user can invoke the agent.

---

## RubyLLM Usage Examples

### Example 1: Basic Chat with Tools

```ruby
# Create chat instance
llm_chat = RubyLLM::Chat.new(
  provider: :openai,
  model: "gpt-4o"
)

# Add messages
llm_chat.add_message(
  role: "system",
  content: "You are a helpful list curator."
)
llm_chat.add_message(
  role: "user",
  content: "Create a list of 5 programming languages"
)

# Register tools
class ListTool < RubyLLM::Tool
  description "Create a list with items"
  param :title, type: :string, desc: "List title"
  param :items, type: :array, desc: "Items to add"

  def name
    "create_list"
  end

  def execute(**kwargs)
    # Execute tool logic
    { list_id: SecureRandom.uuid, created: true }
  end
end

llm_chat.with_tool(ListTool)

# Get response
response = llm_chat.complete

# Check results
if llm_chat.messages.last.tool_calls.present?
  puts "Tools called: #{llm_chat.messages.last.tool_calls.map(&:name).join(', ')}"
else
  puts "Response: #{response.content}"
end

# Check tokens
puts "Tokens: input=#{response.usage.input_tokens}, output=#{response.usage.output_tokens}"
```

### Example 2: Multi-Turn Conversation with Tool Results

```ruby
# Start conversation
llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4o")

llm_chat.add_message(role: "system", content: "You are helpful.")
llm_chat.add_message(role: "user", content: "Create a boat shopping list")

# Register tool
llm_chat.with_tool(CreateListTool)

# First turn: LLM decides to call tool
response1 = llm_chat.complete
# → LLM calls create_list

# Add tool result
tool_call = llm_chat.messages.last.tool_calls.first
llm_chat.add_message(
  role: "tool",
  tool_call_id: tool_call.id,
  content: '{"list_id":"abc","items_created":5}'
)

# Second turn: LLM sees result, decides next action
response2 = llm_chat.complete
# → LLM can call more tools or respond with text

# Now both turns are in message history
puts "Turns: #{llm_chat.messages.count}"
```

### Example 3: Dynamic Tool Creation (Like Listopia)

```ruby
# Build tools based on agent permissions
tools_specs = AgentToolBuilder.tools_for_agent(agent)

tools_specs.each do |tool_spec|
  # Dynamically create tool class at runtime
  tool_class = AgentToolWrapper.create_tool_class(
    tool_spec,
    agent: agent,
    user: user,
    organization: org,
    invocable: invocable,
    run: run
  )

  # Register with chat
  llm_chat.with_tool(tool_class)
end

# LLM can now use all permitted tools
response = llm_chat.complete
```

---

## Example: Creating a Custom Agent

```ruby
# Create a "Priority Analyzer" agent
agent = AiAgent.create!(
  scope: :org_agent,
  organization: current_organization,
  name: "Priority Analyzer",
  slug: "priority-analyzer",
  description: "Analyzes and suggests priority adjustments based on deadlines and dependencies",

  # Core configuration
  persona: "You are a priority management expert. You analyze lists to suggest optimal priority ordering.",
  instructions: "1. Load the list\n2. Identify deadline-driven items\n3. Find dependencies\n4. Suggest reordering\n5. Ask user to approve changes",
  body_context_config: { "load" => "invocable" },
  pre_run_questions: [
    { "key" => "strategy", "question" => "Priority strategy?", "options" => ["deadline-first", "dependency-driven", "effort-based"], "required" => true }
  ],
  trigger_config: { "type" => "manual" },

  # Execution config
  status: :active,
  model: "gpt-4o-mini",
  max_tokens_per_run: 4000,
  max_tokens_per_day: 50_000,
  max_tokens_per_month: 500_000
)

# Grant permissions
agent.ai_agent_resources.create!(resource_type: "list", permission: :read_write)
agent.ai_agent_resources.create!(resource_type: "list_item", permission: :read_write)
agent.ai_agent_resources.create!(resource_type: "user_interaction", permission: :expect_response)
```

---

## Token Management with RubyLLM

RubyLLM automatically tracks token usage from OpenAI responses:

```ruby
response = llm_chat.complete

# Get usage stats from RubyLLM
input_tokens = response.usage.input_tokens      # Tokens in request
output_tokens = response.usage.output_tokens    # Tokens in response
thinking_tokens = response.usage.thinking_tokens || 0  # Extended thinking (GPT-4)

# Store in run
step.update(
  input_tokens: input_tokens,
  output_tokens: output_tokens
)

@run.increment!(:input_tokens, input_tokens)
@run.increment!(:output_tokens, output_tokens)
@run.increment!(:thinking_tokens, thinking_tokens)
@run.increment!(:total_tokens, input_tokens + output_tokens)
```

### Token Budgets

Each agent has enforced quotas:
- `max_tokens_per_run` — Max tokens for a single run (default: 4000)
- `max_tokens_per_day` — Daily quota (default: 50,000)
- `max_tokens_per_month` — Monthly quota (default: 500,000)
- `timeout_seconds` — Max execution time (default: 120s)
- `max_steps` — Max reasoning iterations (default: 20)

The `AgentTokenBudgetService` enforces these before running:

```ruby
budget_check = AgentTokenBudgetService.call(
  agent: @agent,
  estimated_tokens: @agent.max_tokens_per_run
)

return failure("Token budget exceeded") if budget_check.failure?
```

---

## Real-Time Feedback & Observability

**During Execution:**
- Run status updates via Turbo Streams (real-time UI)
- Step-by-step log showing agent reasoning
- Token usage tracked per step
- Event emissions for each state transition

**Events Emitted:**
- `agent_run.started`
- `agent_run.awaiting_input`
- `agent_run.paused` (for HITL)
- `agent_run.resumed`
- `agent_run.completed`
- `agent_run.failed`
- `agent_run.cancelled`

**Notifications:**
- Noticed gem notifications on completion or error
- User feedback forms for rating/improving agents

---

## Troubleshooting

| Problem | Diagnosis | Solution |
|---------|-----------|----------|
| Agent doesn't run | Check `status: :active` and `accessible_by?(user)` | Activate agent, verify user access |
| No embedding generated | OpenAI API key missing or rate-limited | Set `OPENAI_API_KEY`, check quota |
| Pre-run questions not appearing | Questions array empty or malformed | Check `pre_run_questions` JSON schema |
| HITL not pausing | Agent not calling ask_user/confirm_action tools | Update agent instructions to use HITL tools |
| Token budget exceeded | Too many tokens used | Lower `max_tokens_per_run` or increase monthly budget |
| Event-triggered agent not firing | Subscription not active or event_type mismatch | Check `event_subscriptions.rb` and `trigger_config` |
| Scheduled agent missing | Cron expression invalid or `AgentScheduleJob` not running | Fix cron syntax, ensure `AgentScheduleJob` scheduled |

---

## Implementation Notes

- **No cross-run memory yet** — Each run is independent; `recent_runs` context is available (future: persistent memory)
- **Embeddings are optional** — Gracefully skip if OpenAI not configured
- **HITL tools always available** — Not gated by resources
- **Event subscriptions active** — Agents respond immediately to `list_item.completed`, `.created`, `.updated` events
- **RubyLLM integration** — All LLM calls use RubyLLM with OpenAI models

---

## Future Enhancements

1. **Multi-agent orchestration** — Agents delegating to other agents with semantic agent discovery
2. **Persistent memory** — Learn user preferences, maintain conversation history
3. **Advanced RAG** — Agents reasoning over proprietary docs/knowledge bases
4. **Agent teams** — Multiple agents collaborating on complex workflows
5. **Analytics dashboard** — Agent performance trends, HITL frequency, cost tracking
6. **More integrations** — Slack, Calendar, GitHub, Jira via integration framework
7. **Agent marketplace** — Share and discover agents built by the community

---

## References

- **Execution:** `app/services/agent_execution_service.rb`
- **Triggers:** `app/services/agent_trigger_service.rb`
- **Context:** `app/services/agent_context_builder.rb`
- **Tools:** `app/services/agent_tool_builder.rb`, `agent_tool_executor_service.rb`
- **Models:** `app/models/ai_agent.rb`, `ai_agent_run.rb`, `ai_agent_interaction.rb`
- **Jobs:** `app/jobs/agent_run_job.rb`, `agent_event_dispatch_job.rb`, `agent_schedule_job.rb`, `agent_embedding_job.rb`
- **Events:** `config/initializers/event_subscriptions.rb`
- **Seeds:** `db/seeds.rb` (4 system agents with full config)
