```markdown
# Listopia AI Agents Architecture & Guide

## Overview

**AI Agents** are autonomous, LLM-powered workers that help users create, organize, and complete **Lists** and **Tasks** (List Items). They can:

- Reason, plan, reflect, iterate, and self-correct.
- Read/write Lists, Tasks, and related data.
- Collaborate via structured orchestration (supervisor, sequential, parallel, or agents-as-tools).
- Integrate securely with external services via **Integrations**.
- Send notifications and request user input via **noticed** + new HITL tools.
- Maintain context/memory and emit real-time events for visibility.
- Run asynchronously with full observability, streaming, and human-in-the-loop control.

**Core Principles (2026 Best Practices)**:
- **Stateful & Event-Driven**: Persistent run state + callbacks (inspired by LangGraph checkpointing and langchainrb Assistant callbacks).
- **Human-in-the-Loop (HITL)**: Agents pause for confirmation/questions (LangGraph-style interrupts).
- **Real-Time Feedback**: Streaming + Event Manager for live "what is the agent doing?" visibility.
- **Reliable Orchestration**: Reflection, validation, retries, and max-depth guardrails.
- **Ruby-Native**: All LLM work via `ruby_llm`; events and tools are lightweight Rails-friendly.

**Key Technologies**:
- `ruby_llm`: All LLM calls (chat, tools, structured outputs, streaming).
- `noticed`: In-app, email, push notifications.
- Turbo Streams + Action Cable: Real-time UI updates from events.

---

## Agent Scopes & Access Control

(Unchanged – solid foundation.)

- **System / Org / Team / User** scopes with `accessible_by?` and `manageable_by?`.
- Sub-agent invocations respect the invoking user's permissions.

---

## Agent Configuration

### Core Fields
- `name`, `description`, `prompt` (system instruction + persona).
- `scope`, `status` (`draft` / `active` / `paused` / `archived`).
- `model` (via `ruby_llm` registry).
- `role` (Planner, Researcher, Executor, Reviewer, Supervisor).
- `orchestration_mode` (`single` / `supervisor` / `sequential` / `parallel` – default: `single`).

### Execution Controls
- `timeout_seconds` (default 300).
- `max_steps` (default 20).
- Token budgets + rate limits.
- `enable_streaming` (boolean – enables partial LLM output streaming).

### Input Parameters & Memory
- JSONB schema for parameters (validated + injected).
- Short-term: message history + `shared_state` (JSONB).
- Long-term: Optional RAG via vector embeddings (powered by `ruby_llm`).

### Resources (Enhanced)
| Resource Type        | Permissions                          | Purpose |
|----------------------|--------------------------------------|---------|
| `list` / `list_item` | read_only, write_only, read_write   | Core data |
| `integration`        | read_only, read_write, expect_response | External services (proxied) |
| `agent`              | invoke, poll                        | Sub-agents |
| `web_search` / `knowledge` | read_only                      | Search / RAG |
| `notification`       | send                                | Noticed gem notifications |
| `user_interaction`   | ask, confirm                        | HITL questions & approvals |

- **New**: `user_interaction` resource enables agents to pause and interact directly with users.

---

## Orchestration Layer (Event-Driven)

**New: Event Manager** – Central component (inspired by LangGraph events, AutoGen messaging, and langchainrb callbacks). It decouples execution from side-effects and powers real-time feedback.

### Event Manager Responsibilities
- Emits typed events during execution:
  - `llm_call_started`, `llm_stream_chunk`, `llm_call_completed`
  - `tool_call_executed` (with result)
  - `user_interaction_requested` (pause for input)
  - `sub_agent_invoked`, `reflection_completed`
  - `run_status_updated`, `run_completed`
- Subscribers:
  - Turbo Streams / Action Cable (live UI updates).
  - Noticed gem (notifications).
  - Logging / tracing / analytics.
  - Custom webhooks (future).

**Implementation**: A lightweight `AiAgentEventManager` service that broadcasts via `ActiveSupport::Notifications` or a simple Pub/Sub. `AgentExecutionService` registers callbacks (similar to langchainrb’s `add_message_callback` and `tool_execution_callback`).

### Supported Orchestration Patterns
1. **Single Agent** – ReAct + reflection loop.
2. **Supervisor** – Manager decomposes and delegates (CrewAI-style roles).
3. **Sequential / Parallel** – Fixed or concurrent handoffs.
4. **Agents as Tools** – LLM decides invocations.
5. **Graph-like** – Conditional routing via events (LangGraph-inspired).

**Max depth**: 4. Persistent state via `AiAgentRun` checkpoints.

---

## Execution Flow (with Real-Time Feedback & HITL)

1. User invokes agent (`user_input`, `input_parameters`, optional `invocable`).
2. `AiAgentRun` created (`status: pending`). `AgentRunJob` enqueued.
3. `AgentExecutionService.call(run:)` (uses `ruby_llm` exclusively):
   - Checks (permissions, budget, timeout).
   - Builds context (prompt + memory + parameters).
   - **Main event-driven loop** (up to `max_steps`):
     - LLM call via `ruby_llm` (with tools + streaming if enabled).
     - Event Manager broadcasts `llm_stream_chunk` → UI shows live thinking.
     - Tool calls → `AgentToolExecutorService` → event `tool_call_executed`.
     - Sub-agent calls → child run + events.
     - **Reflection** after key steps.
     - **HITL**: If agent uses `user_interaction` tool → emit `user_interaction_requested`, pause job (state saved), notify user via Noticed.
   - User responds via UI → resume run with provided input.
4. Final synthesis → `result_data`.
5. Event `run_completed` → Noticed notification + feedback prompt.

**Real-Time User Feedback**:
- Run View shows live status badges: "Thinking…", "Waiting for your input", "Running sub-agent X", "Step 5/12".
- Streaming partial LLM outputs (via `ruby_llm` block).
- Event-driven Turbo updates for every step/tool/reflection.
- Progress bar + step log (reasoning + results).

**Agent ↔ User Interaction (HITL)**:
- Agent tools: `ask_user(question, options)` or `confirm_step(description, expected_outcome)`.
- Execution pauses (run status → `paused_for_input`).
- User sees modal/form in Run View with question + reply field.
- Reply injected as tool result → resume (LangGraph-style interrupt).
- Examples:
  - "Shall I delete these 3 completed tasks?" → user confirms/rejects.
  - "What priority should this new list have?" → user answers.
  - "I found 5 potential duplicates – review them?" → user approves list.

**Noticed Integration**: Automatic on `user_interaction_requested` or `run_completed`.

---

## Tools System

Tools built dynamically from resources (`AgentToolBuilder`).

**Key Tools** (all via `ruby_llm` function calling):
- List/Task CRUD.
- Secure Integration calls.
- Invoke/poll agents.
- Send notification (noticed).
- **New HITL tools**: `ask_user`, `confirm_step`.
- Reflection / validation / web search.

**Execution**:
- `AgentToolExecutorService`: permission check → sanitize → execute → structured result → Event Manager broadcast.
- HITL tools create `AiAgentInteraction` record and pause.

---

## Data Models (Key Additions)

- `AiAgent`: Add `enable_streaming`.
- `AiAgentResource`: Support `user_interaction` type.
- `AiAgentRun`: Add `shared_state`, `orchestration_plan`, `current_checkpoint` (for resume).
- **New**: `AiAgentInteraction` (for HITL questions/answers).
- `AiAgentRunStep`: Enhanced with `event_type` and `payload`.
- Events logged via Event Manager for full audit trail.

---

## UI & Real-Time Updates

- **Browse / Show**: Role, mode, resources (incl. HITL capability), live run status.
- **Invoke Form**: Parameters + "Enable live streaming".
- **Run View** (real-time via Turbo + Events):
  - Live step-by-step log with reasoning.
  - Streaming text output.
  - Status: "Running", "Paused for input", etc.
  - HITL modal when interaction requested.
  - Pause/Resume/Cancel + feedback form.
- **Post-Run**: Auto Noticed summary + rating/feedback (existing `AiAgentFeedbacks`).

---

## Notifications & User Feedback

- **During Run**: Noticed + in-app (via events) for "Agent needs your input".
- **After Run**: Completion summary, success rate, token usage.
- **Feedback Loop**: Users rate runs; high-level feedback can auto-improve prompts (future).

---

## Security, Reliability & Performance

- Multi-layer auth + secure proxy for integrations.
- `ruby_llm` structured outputs + server-side validation.
- Event Manager ensures no silent failures (all steps observable).
- Checkpoints for safe pause/resume.
- Retries, timeouts, token budgets.
- Observability: Full event trace per run.

---

## Future Enhancements (Prioritized)

1. Visual graph builder for orchestration plans (LangGraph-style).
2. Advanced RAG + long-term memory.
3. Agent teams with persistent shared context.
4. Analytics dashboard (event trends, HITL frequency).
5. More Noticed templates and delivery channels.

---

## Troubleshooting

- **No live updates**: Check Event Manager subscriptions / Turbo connection.
- **HITL not triggering**: Verify `user_interaction` resource is enabled.
- **Agent stuck**: Inspect events log or job queue (checkpoints help resume).
- **Poor collaboration**: Use supervisor mode + clearer role prompts.
- **ruby_llm issues**: Ensure model supports tools/streaming; check callbacks.
