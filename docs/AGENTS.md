# AI Agents Architecture & Guide

This document describes the AI Agent system: how agents work, access control, resource management, execution flow, and how to extend the system.

## Overview

**AI Agents** are autonomous LLM-powered workers that can:
- Read and modify lists and list items
- Invoke other agents (orchestration)
- Execute tools with defined permissions
- Track execution progress and results
- Run in the background via job queues

Agents are **scoped** (system-wide, org-level, team-level, or user-specific) and have **resources** that define what tools they can access at runtime.

## Agent Scopes & Access Control

### Scope Hierarchy

```
System Agent
├─ Created by Listopia team
├─ Visible to all users (if active)
├─ Can be invoked by anyone (if active)
└─ Cannot be edited/deleted by anyone

Org Agent
├─ Created by org admin/owner
├─ Visible only to org members
├─ Can be invoked by org members (if active)
└─ Can only be edited by org admin/owner

Team Agent
├─ Created by team admin or org admin/owner
├─ Visible only to team members
├─ Can be invoked by team members (if active)
└─ Can only be edited by team admin or org admin/owner

User Agent
├─ Created by individual user
├─ Visible only to owner
├─ Can only be invoked by owner (if active)
└─ Can only be edited by owner
```

### Authorization Rules (from `AiAgent` model)

```ruby
# Can this user invoke/use this agent?
def accessible_by?(user)
  case scope
  when "system_agent"
    status_active?
  when "org_agent"
    status_active? && user.in_organization?(organization)
  when "team_agent"
    status_active? && teams.any? { |t| t.member?(user) }
  when "user_agent"
    status_active? && self.user == user
  end
end

# Can this user edit/manage this agent?
def manageable_by?(user)
  case scope
  when "system_agent"
    false  # no one edits system agents from UI
  when "org_agent"
    organization && organization.membership_for(user)&.role.in?(%w[admin owner])
  when "team_agent"
    teams.any? { |t| t.user_is_admin?(user) } ||
      (organization && organization.membership_for(user)&.role.in?(%w[admin owner]))
  when "user_agent"
    self.user == user
  end
end
```

**UI Translation:**
- **View** agent details → checks `accessible_by?`
- **Invoke** agent → checks `accessible_by?`
- **Edit** agent → checks `manageable_by?` (shows Edit button, calls `authorize @agent` in controller)
- **Delete** agent → checks `manageable_by?`
- **Add/Edit/Delete resources** → checks parent agent's `manageable_by?`

## Agent Configuration

### Basic Fields

| Field | Type | Purpose |
|-------|------|---------|
| `name` | string | Display name (e.g., "Research Assistant") |
| `description` | text | What the agent does |
| `prompt` | text | System instruction (LLM persona & behavior) |
| `scope` | enum | system_agent, org_agent, team_agent, user_agent |
| `status` | enum | draft, active, paused, archived |
| `model` | string | LLM model (gpt-5-pro, gpt-4o, o1, etc.) |

### Execution Controls

| Field | Default | Purpose |
|-------|---------|---------|
| `timeout_seconds` | 120 | Total execution timeout |
| `max_steps` | 20 | Max agentic loop iterations |
| `max_tokens_per_run` | 4000 | Token budget per run |
| `rate_limit_per_hour` | 10 | Invocations per hour limit |
| `max_tokens_per_day` | 50000 | Daily token budget |
| `max_tokens_per_month` | 500000 | Monthly token budget |

### Parameters (NEW)

Users can define what input parameters the agent accepts:

```json
{
  "task_description": "What the user wants to accomplish",
  "priority_level": "low, medium, high, or urgent",
  "target_audience": "who is this for?"
}
```

Parameters are:
- Stored as JSONB on the agent
- Displayed on the show page for reference
- Not yet automatically passed to the LLM (future enhancement)

### Resources (NEW)

**Resources** define what tools an agent can use at runtime. Each resource has:

| Field | Options | Purpose |
|-------|---------|---------|
| `resource_type` | list, list_item, web_search, agent, calendar, slack, google_drive, external_api, database_query | What type of resource |
| `permission` | read_only, write_only, read_write, expect_response | Access level |
| `description` | text | What this resource is for |
| `resource_identifier` | string | Optional: specific UUID to restrict to one resource |
| `enabled` | boolean | Is it active? |

**Example:**
- Type: `list`, Permission: `read_write` → agent can read/write all lists
- Type: `agent`, Permission: `read_write` → agent can invoke other agents and check their status

## Execution Flow

### Agent Run Lifecycle

```
1. User invokes agent
   ├─ Input: user_input (natural language instruction)
   ├─ Input: input_parameters (optional structured data)
   └─ Input: invocable (optional List or ListItem context)

2. AiAgentRun created (status: pending)

3. AgentRunJob enqueued (background)

4. AgentExecutionService.call(run:)
   ├─ Check token budget
   ├─ Set run status to running
   ├─ Build initial messages (system prompt + user input)
   │
   └─ Loop (max: max_steps or 30)
      ├─ Call LLM with available tools
      ├─ Parse response for tool_calls
      │
      ├─ If tool_calls present:
      │  ├─ For each tool_call:
      │  │  ├─ AgentToolExecutorService.call(tool_call:)
      │  │  ├─ Execute tool (read_list, create_item, invoke_agent, etc.)
      │  │  └─ Return result as tool message
      │  │
      │  └─ Add tool results to message history
      │
      └─ If no tool_calls (or stop reason):
         └─ Run complete

5. Record final summary and result_data

6. Update run status to completed/failed/cancelled
```

**Timeout:** Wraps entire execution in `Timeout.timeout(timeout_seconds)`

**Token Tracking:**
- Records input_tokens, output_tokens per step
- Checks daily/monthly budgets before running
- Increments agent's token usage counters

### Message Flow

```ruby
messages = [
  { role: "system", content: agent.prompt },
  { role: "user", content: user_input }
]

# Agentic loop:
loop do
  response = llm.call(messages, tools: available_tools)

  if response.tool_calls.present?
    messages << { role: "assistant", content: nil, tool_calls: response.tool_calls }
    response.tool_calls.each do |call|
      result = execute_tool(call)
      messages << { role: "tool", tool_call_id: call.id, content: result.to_json }
    end
  else
    break  # No more tools requested
  end
end
```

## Tools System

### Available Tools

Tools are defined in `AgentToolBuilder::TOOL_SPECS`:

| Tool | Purpose | Permissions |
|------|---------|-------------|
| `read_list` | Get list metadata | read_only, read_write |
| `read_list_items` | Get all items in list | read_only, read_write |
| `create_list_item` | Create new item | write_only, read_write |
| `update_list_item` | Modify item fields | read_write |
| `complete_list_item` | Mark item complete | read_write |
| `invoke_agent` | Call another agent | (agent resource) |
| `poll_agent_run` | Check sub-agent status | (agent resource) |
| `web_search` | Search web (stub) | (web_search resource) |

### Tool Selection

At runtime, `AgentToolBuilder.tools_for_agent(agent)` returns only tools that match the agent's resources:

```ruby
def self.tools_for_agent(agent)
  agent.ai_agent_resources.enabled.map do |resource|
    tool_for_resource(resource)  # Maps resource to tool(s)
  end.compact
end

def self.tool_for_resource(resource)
  case resource.resource_type
  when "list"
    if resource.permission_read_write?
      [ TOOL_SPECS[:read_list], TOOL_SPECS[:read_list_items],
        TOOL_SPECS[:create_list_item], TOOL_SPECS[:update_list_item] ]
    end
  when "agent"
    [ TOOL_SPECS[:invoke_agent], TOOL_SPECS[:poll_agent_run] ]
  # ... etc
  end
end
```

### Tool Execution

`AgentToolExecutorService` handles each tool call:

```ruby
def initialize(tool_call:, agent:, user:, organization:, invocable: nil)
  @tool_call = tool_call
  @agent = agent
  @function_name = tool_call.dig("function", "name")
end

def call
  # 1. Verify agent has permission for this tool
  unless agent_has_permission_for?(resource_type, @function_name)
    return failure(message: "Agent does not have permission for #{@function_name}")
  end

  # 2. Execute the handler
  send(TOOL_HANDLERS[@function_name])
end
```

## Orchestration (Agent → Agent)

Agents can invoke other agents via the `invoke_agent` tool:

```ruby
def handle_invoke_agent
  agent_id = @arguments["agent_id"]
  sub_agent = AiAgent.kept.find_by(id: agent_id)

  # Check user can access sub-agent
  unless sub_agent.accessible_by?(@user)
    return failure(message: "You don't have access to this agent")
  end

  # Check orchestration depth (max 3 levels)
  current_depth = current_run_depth + 1
  return failure(message: "Max depth exceeded") if current_depth > 3

  # Create child run (async)
  child_run = AiAgentRun.create!(
    ai_agent: sub_agent,
    user: @user,
    organization: @organization,
    parent_run_id: current_run_id,
    user_input: @arguments["user_input"],
    input_parameters: @arguments["parameters"] || {},
    metadata: { depth: current_depth }
  )

  AgentRunJob.perform_later(child_run.id)

  success(data: { child_run_id: child_run.id, status: "pending" })
end
```

**Key Points:**
- Sub-agents run **asynchronously** (background job)
- Parent agent uses `poll_agent_run` to check status
- Max depth: 3 levels of nesting
- User must have access to all invoked agents

## Data Models

### AiAgent

```ruby
class AiAgent < ApplicationRecord
  has_many :ai_agent_resources, dependent: :destroy
  has_many :ai_agent_runs, dependent: :destroy
  has_many :ai_agent_team_memberships
  has_many :teams, through: :ai_agent_team_memberships
  belongs_to :organization, optional: true
  belongs_to :user, optional: true

  enum :scope, { system_agent: 0, org_agent: 1, team_agent: 2, user_agent: 3 }
  enum :status, { draft: 0, active: 1, paused: 2, archived: 3 }

  # Soft-delete via discard gem
  include Discard::Model

  # Full audit trail via Logidze
  has_logidze

  # Tags for categorization
  acts_as_taggable_on :tags
end
```

### AiAgentResource

```ruby
class AiAgentResource < ApplicationRecord
  belongs_to :ai_agent

  RESOURCE_TYPES = %w[
    list list_item web_search calendar slack
    google_drive external_api database_query agent
  ].freeze

  enum :permission, {
    read_only: 0,
    write_only: 1,
    read_write: 2,
    expect_response: 3
  }, prefix: true

  validates :resource_type, inclusion: { in: RESOURCE_TYPES }
end
```

### AiAgentRun

```ruby
class AiAgentRun < ApplicationRecord
  belongs_to :ai_agent
  belongs_to :user
  belongs_to :organization
  belongs_to :invocable, polymorphic: true, optional: true
  belongs_to :parent_run, class_name: "AiAgentRun", optional: true
  has_many :ai_agent_run_steps, dependent: :destroy
  has_many :child_runs, class_name: "AiAgentRun", foreign_key: :parent_run_id

  enum :status, {
    pending: 0,      # queued, waiting to start
    running: 1,      # actively executing
    paused: 2,       # user paused mid-execution
    completed: 3,    # finished successfully
    failed: 4,       # error occurred
    cancelled: 5     # user cancelled
  }, prefix: true

  # JSON fields
  input_parameters: jsonb   # User-provided params
  result_data: jsonb         # Final result/output

  # Tracking
  steps_completed: integer   # How many agentic steps done
  steps_total: integer       # How many steps planned
  input_tokens: integer      # Tokens consumed
  output_tokens: integer     # Tokens generated
  total_tokens: integer      # Sum
  thinking_tokens: integer   # Extended thinking tokens
  processing_time_ms: integer # How long it took
end
```

### AiAgentRunStep

```ruby
class AiAgentRunStep < ApplicationRecord
  belongs_to :ai_agent_run

  enum :step_type, { llm_call: 0, tool_call: 1 }
  enum :status, { pending: 0, running: 1, completed: 2, failed: 3 }

  # Captures exactly what happened in this step
  input: jsonb    # Tool arguments or LLM messages
  output: jsonb   # Tool result or LLM response
end
```

## Routes & Controllers

### Routes
```ruby
resources :ai_agents, path: "agents" do
  resources :ai_agent_resources, path: "resources", except: [ :index, :show ]
  member do
    post :invoke
    get  :runs
  end
  collection do
    get :browse    # Browse all available agents
    get :my_agents # User's personal agents
  end
end

resources :ai_agent_runs, path: "agent_runs", only: [ :show, :index, :create ] do
  member do
    patch :pause
    patch :resume
    delete :cancel
  end
  resources :ai_agent_feedbacks, path: "feedback", only: [ :create ]
end
```

### Key Controller Actions

**AiAgentsController#invoke**
- Creates `AiAgentRun` with user_input and input_parameters
- Enqueues `AgentRunJob`
- Responds with Turbo Stream (updates progress UI)

**AiAgentResourcesController#[create/update/destroy]**
- Checks `AiAgentResourcePolicy` (delegates to parent agent's `manageable_by?`)
- Responds with Turbo Stream (inline add/edit/delete)

## UI & Real-Time Updates

### Browse View (`/agents/browse`)
- Shows available agents grouped by scope
- Agent cards display: name, description, rating, run count, tags
- Click "View" to see details
- Tags displayed as pill badges

### Show View (`/agents/:id`)
- Agent details, stats (run count, success rate, rating)
- **Invoke form** (if accessible)
  - Text area for user_input
  - Button to start run
- **Input Parameters** section (if defined)
  - Read-only display of expected parameters
- **Resources & Tools** section
  - List of configured resources
  - For each resource: type, permission, enabled status, tools it enables
  - "Add Resource" button (if manageable)
  - Edit/Delete buttons per resource (if manageable)
- **Recent Runs** section
  - Last 5 runs by this user
  - Status badge and link to full run view

### Edit View (`/agents/:id/edit`)
- All configuration fields: name, description, prompt, scope, status, model, etc.
- **Execution Controls**: timeout, max_steps, token budgets, rate limits
- **Input Parameters**: JSON textarea for defining parameters
- **Tags**: comma-separated list

### Run View (`/agent_runs/:id`)
- Real-time progress via Turbo Streams
- Step-by-step execution log
- Tool calls and results
- Final result summary
- Pause/Resume/Cancel buttons

## Backend Jobs

### AgentRunJob

```ruby
class AgentRunJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = AiAgentRun.find(run_id)
    AgentExecutionService.call(agent_run: run)
  end
end
```

Runs in background queue; updates run status throughout execution.

## Performance Considerations

### Token Budget Checks
- Before each run: `AgentTokenBudgetService` checks daily/monthly limits
- Per-step: `AgentExecutionService` tracks token usage
- Increments agent counters for accounting

### N+1 Prevention
- Agent show page: `includes(:ai_agent_resources, :teams)` to avoid loading per-resource
- Browse page: Uses `policy_scope` for efficient scoped queries

### Timeouts
- **Overall timeout**: `timeout_seconds` (default 120s) wraps entire execution
- **Per-step timeout**: (not yet implemented) could add per-tool and per-LLM-call timeouts
- **Current limitation**: Reflection/extended thinking consumes the overall budget

## Security

### Authorization Layers
1. **Policy**: `AiAgentPolicy` checks scope + membership
2. **Controller**: `authorize @agent` enforces policy
3. **Resource permission**: `AgentToolBuilder` only exposes permitted tools
4. **Tool executor**: Checks agent has permission before executing tool

### Data Access
- All queries scoped to organization via `Current.organization`
- LLM only sees what the user can access (through tool result permissions)
- Sub-agent access: checked against user's accessible agents

### Sensitive Operations
- System agents: read-only (no UI edit/delete)
- Resource management: gated by parent agent permissions
- Token budgets: prevent runaway spending
- Rate limiting: prevent abuse (10/hour default)

## Future Enhancements

1. **Parameters Integration**
   - Pass input_parameters to LLM as context
   - Validate user input against parameter schema

2. **Timeout Improvements**
   - Per-tool timeouts
   - Per-LLM-call timeouts
   - Separate thinking budget from execution budget
   - Progress indicators for long-running operations

3. **Better Monitoring**
   - Dashboard of token usage trends
   - Agent performance metrics
   - Error tracking and alerting

4. **Advanced Orchestration**
   - Agent teams (agents with shared context)
   - Conditional agent routing
   - Agent skill discovery (auto-discover available tools)

5. **UI Enhancements**
   - Visual builder for agent logic
   - Test harness for agent prompts
   - Custom tool builder UI

## Troubleshooting

### Agent runs stuck in "running"
- Check `Timeout::Error` in logs — exceeded timeout
- Check background job queue — `AgentRunJob` may not have run

### Authorization errors on invoke
- Verify agent is `status_active?`
- Verify user in correct organization/team/is owner
- Check `accessible_by?` method

### Tools not available
- Verify resource exists and is `enabled: true`
- Verify resource type matches tool (e.g., "list" for list tools)
- Check permission level (read_only vs write_only vs read_write)

### Token budget exceeded
- Check daily/monthly limits on agent
- Verify `max_tokens_per_run` is set appropriately
- Consider increasing limits or breaking into multiple runs
