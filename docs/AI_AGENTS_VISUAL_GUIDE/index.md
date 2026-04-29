# AI Agents Visual Guide

Comprehensive visual documentation for Listopia's AI Agent system. This guide explains how agents work, how to use them from the chat interface, and how to access them from the UI.

---

## Table of Contents

1. [Quick Overview](#quick-overview)
2. [How AI Agents Work](#how-ai-agents-work)
3. [Using Agents from Chat](#using-agents-from-chat)
4. [Using Agents from the UI](#using-agents-from-the-ui)
5. [Agent Lifecycle & Execution](#agent-lifecycle--execution)
6. [Trigger Types](#trigger-types)
7. [Human-in-the-Loop](#human-in-the-loop)
8. [Real-World Examples](#real-world-examples)

---

## Quick Overview

AI Agents are autonomous LLM-powered workers in Listopia that help you manage lists and tasks. They can:

✅ **Break down complex goals** into actionable task lists
✅ **Run automatically** on schedules or when events occur
✅ **Ask clarifying questions** before executing
✅ **Request approval** before significant actions (human-in-the-loop)
✅ **Generate reports** across all your lists
✅ **Research and enrich** items with external information

---

## How AI Agents Work

### Architecture Overview

![Agent Architecture](./architecture.svg)

The AI Agent system consists of five core components:

1. **Trigger System** — How agents are invoked (manual, event-based, or scheduled)
2. **Agent Configuration** — Persona, instructions, and execution parameters
3. **Execution Engine** — Coordinates the agent's reasoning and tool usage
4. **Tool Builder** — Defines what the agent can do (list CRUD, web search, etc.)
5. **Memory System** — Provides context from lists and prior runs

### Core Configuration (5 Key Fields)

Every agent requires these essential settings:

**1. Persona** — WHO the agent is
> "You are a senior project manager expert at decomposing complex goals into clear tasks."

**2. Instructions** — WHAT the agent does (step-by-step)
```
1. Understand the goal (ask clarifying questions if needed)
2. Identify major phases and milestones
3. Break into specific, actionable tasks
4. Assign priority and effort estimate to each
5. Ask user to confirm before creating items
```

**3. Body Context Config** — WHAT context to auto-load
- `{ "load": "invocable" }` — Current list/item being worked on
- `{ "load": "all_lists" }` — All organization lists (for reports)
- `{ "load": "recent_runs" }` — Prior agent run summaries (memory)

**4. Pre-Run Questions** — WHAT to ask the user first
```json
[
  {
    "key": "goal",
    "question": "What is your main goal?",
    "required": true
  },
  {
    "key": "deadline",
    "question": "Do you have a deadline? (optional)",
    "required": false
  }
]
```

**5. Trigger Config** — HOW the agent is invoked
- Manual: `{ "type": "manual" }` — User clicks "Run"
- Event: `{ "type": "event", "event_type": "list_item.completed" }`
- Scheduled: `{ "type": "schedule", "cron": "0 9 * * 1" }` — Every Monday 9am

---

## Using Agents from Chat

### Chat Integration Flow

![Chat Integration](./chat-integration.svg)

Agents can be invoked directly from the chat interface using natural language.

### Step-by-Step: Invoking an Agent from Chat

#### 1. Start a Chat Conversation
Open the list chat panel and describe what you need.

#### 2. Natural Language Agent Invocation
```
You: "Break down the Q1 roadshow planning into tasks"
```

The chat system detects this is agent-like work and can:
- Automatically invoke the **Task Breakdown Agent**
- Pass your request as the `input` parameter
- Execute the agent in the background

#### 3. Pre-Run Questions (if configured)
If the agent has pre-run questions, you'll see a form:
```
❓ Task Breakdown Agent
   "What is your main goal?" → [Your answer]
   "Do you have a deadline?" → [Optional]
```

#### 4. Real-Time Progress Updates
As the agent executes:
- Chat shows "Agent running..." indicator
- You see step-by-step progress
- Token usage is tracked in real-time

#### 5. Results Display
Once complete:
```
✅ Task Breakdown Complete
   12 tasks created in "Q1 Roadshow Planning"
   High priority: 4 items
   Medium priority: 6 items
   Low priority: 2 items

   [View in list] [Refine] [Share]
```

### Agent Response in Chat

When an agent completes, the chat shows:

- **Summary** — Overview of what was done
- **Results Preview** — Items created or modified
- **Next Steps** — Suggestions for follow-up actions
- **Action Buttons** — View in UI, refine, share, etc.

### Multi-Turn Agent Interactions

Agents with **human-in-the-loop** (HITL) support pausing for user input:

```
Agent: "I found 5 potential duplicate items. Should I delete them?"
       [Yes, delete them] [No, keep them] [Review first]

You: [Click "Review first"]

Agent: "Here are the 5 duplicates: [list]
        After review, delete them now?"
       [Confirm] [Cancel]
```

---

## Using Agents from the UI

### UI Navigation & Access

![UI Usage](./ui-usage.svg)

There are multiple ways to access agents from the Listopia UI:

### 1. **Agent Library** (`/agents`)
Browse all available agents:
- **System Agents** — Built-in agents (Task Breakdown, Status Report, etc.)
- **Organization Agents** — Custom agents your team created
- **Team Agents** — Agents specific to your team
- **Personal Agents** — Your own custom agents

Each agent shows:
- Name and description
- Trigger type (manual, event, scheduled)
- Last run details
- Action buttons: [Run], [Edit], [History], [Settings]

### 2. **Quick Agent Run** (from list view)
In any list, you'll see an **"Agents"** menu:
```
📋 My Shopping List
  ... [More] ▼
      ├─ Run Agent
      │  ├─ Task Breakdown
      │  ├─ List Organizer
      │  └─ Research Agent
      └─ Agent History
```

Click any agent to run it on the current list.

### 3. **Agent Config & Management**
Create or edit agents at `/agents/new` or `/agents/:id/edit`:

```
✏️ Create New Agent

Name: [Priority Analyzer]
Description: [Analyzes and suggests priority adjustments]

Configuration:
  Persona: [Who is the agent?]
  Instructions: [What does it do?]
  Body Context: [What context to load?]

Trigger:
  ○ Manual (user clicks "Run")
  ○ Event-triggered (when [event_type] occurs)
  ○ Scheduled (cron: [0 9 * * 1])

Resources (what the agent can do):
  ☑ Read lists
  ☑ Read/write items
  ☑ Ask user questions
  ☐ Search the web
  ☐ Invoke other agents

Pre-Run Questions:
  + Add question
  - Remove

[Save Agent] [Test Run] [Cancel]
```

### 4. **Agent Run History** (`/agents/:id/runs`)
View all past executions:
- Status (completed, failed, paused)
- Execution time and tokens used
- Items created/modified
- User feedback/ratings

### 5. **Agent Settings & Permissions**
Configure what each agent can access:
- **Resources** — Which tools the agent can use
- **Token Budgets** — Daily/monthly limits
- **Execution Timeout** — Max execution duration
- **Visibility** — Who can see/run this agent

### 6. **Real-Time Agent Execution**
When running an agent, watch:
```
🔄 Agent Running: Task Breakdown

Progress:
  Step 1: Analyzing goal... ✓
  Step 2: Identifying phases... ⏳
  Step 3: Creating tasks...
  Step 4: Assigning priorities...
  Step 5: Requesting confirmation...

Tokens Used: 1,250 / 4,000

[Pause] [Cancel]
```

On completion:
```
✅ Complete!

Created 12 items:
  • Phase 1: Planning (3 items)
  • Phase 2: Execution (5 items)
  • Phase 3: Review (4 items)

Total time: 12.5 seconds
Tokens used: 2,180 / 4,000

[View List] [Rate Agent] [Share] [Run Again]
```

---

## Agent Lifecycle & Execution

### Full Execution Flow

![Agent Lifecycle](./lifecycle.svg)

Understanding the lifecycle helps you know what's happening at each stage:

#### 1. **Trigger** (initialization)
- Manual: User clicks "Run Agent"
- Event: System detects `list_item.completed` event
- Scheduled: Cron job fires (e.g., Monday 9am)

#### 2. **Create Run Record** (status: `pending`)
```
AiAgentRun created with:
  - Agent reference
  - Trigger type
  - User input (if manual)
  - Initial context
```

#### 3. **Check for Pre-Run Questions** (status: `awaiting_input`)
If the agent has pre-run questions:
- Form displayed to user
- User answers stored
- Job enqueued when submitted

#### 4. **Build Context** (`AgentContextBuilder`)
System composes the agent's system prompt:
```
🧠 System Prompt:

Your Persona:
[Agent's persona/role]

Your Instructions:
[Step-by-step instructions]

Available Context:
[Current list details, items, recent runs, etc.]

User Input:
[Your request/goal]

User Answers:
[Pre-run question responses]

Available Tools:
[List of tools agent can use]
```

#### 5. **Execute with LLM** (`AgentExecutionService`)
The LLM (GPT-4 mini) processes:
- Reads the system prompt
- Generates reasoning/plan
- Calls tools (read list, create item, etc.)
- Receives tool results
- Continues until done

#### 6. **Tool Execution Loop** (`AgentToolExecutorService`)
For each tool call:
```
Agent calls: create_list_item(title: "...", priority: "high")
  ↓
Tool executor validates permissions
  ↓
Tool executes (creates item in database)
  ↓
Result fed back to LLM
  ↓
LLM continues reasoning
```

#### 7. **Human-in-the-Loop (if needed)** (status: `paused`)
If agent calls `ask_user` or `confirm_action`:
```
Agent paused. Awaiting user response:
  "Should I mark these 5 items as high priority?"
  [Yes] [No] [Review]

User clicks response
  ↓
Response stored
  ↓
Agent resumes with user's answer
```

#### 8. **Completion** (status: `completed` or `failed`)
Agent stops when:
- No more tool calls
- Token budget exceeded
- Timeout reached
- Error encountered

Results:
- Items created/modified
- Events emitted (`agent_run.completed`)
- Notifications sent
- User feedback collected

---

## Trigger Types

### Three Ways to Invoke Agents

![Triggers](./triggers.svg)

#### 1. **Manual Triggers** (User-Initiated)
```
User clicks [Run Agent] → AgentTriggerService.trigger_manual()
  → AiAgentRun created
  → Agent executes immediately (or after pre-run questions)
```

**When to use:**
- Breaking down a goal when you need it
- Researching specific items
- Running cleanup/reorganization on demand

**Configuration:**
```json
{ "type": "manual" }
```

#### 2. **Event-Triggered** (Automatic on Events)
```
User marks item "Complete"
  → Event: list_item.completed
  → AgentEventDispatchJob fires
  → List Organizer Agent auto-runs
  → Agent suggests reorganization
```

**When to use:**
- Auto-reorganize when tasks complete
- Notify on status changes
- Trigger research when items are added

**Configuration:**
```json
{
  "type": "event",
  "event_type": "list_item.completed"
}
```

**Available Events:**
- `list_item.created` — Item added
- `list_item.updated` — Item modified
- `list_item.completed` — Item marked done
- `list_item.assigned` — Item assigned to user
- `list.created` — New list created

#### 3. **Scheduled/Cron** (Regular Intervals)
```
Every Monday 9:00 AM
  → AgentScheduleJob evaluates cron
  → Status Report Agent auto-runs
  → Sends weekly summary to your inbox
```

**When to use:**
- Weekly status reports
- Daily digest emails
- Monthly cleanup/archival
- Recurring tasks

**Configuration:**
```json
{
  "type": "schedule",
  "cron": "0 9 * * 1"
}
```

**Cron Syntax Examples:**
- `0 9 * * 1` — Every Monday at 9am
- `0 9 * * 1-5` — Weekdays at 9am
- `*/15 * * * *` — Every 15 minutes
- `0 0 1 * *` — 1st of month at midnight

---

## Human-in-the-Loop

### Pausing for User Approval

![HITL Flow](./hitl-flow.svg)

Agents can pause mid-execution to request user input.

### Two HITL Tools

#### 1. **`ask_user(question, options[])`**
Ask a free-form or multiple-choice question:

```
Agent: "I found 5 potential duplicates. What should I do?"

Options:
  [Yes, delete them]
  [No, keep them]
  [Review first]

User: [Clicks "Review first"]

Agent resumes with user's choice and continues...
```

#### 2. **`confirm_action(description, expected_outcome)`**
Request approval before a significant change:

```
Agent: "I'm about to re-prioritize 12 items.
        This will move 8 to 'High' and 4 to 'Low'.
        Do you approve?"

[Confirm] [Cancel] [Review Changes]

User: [Clicks "Confirm"]

Agent proceeds with the re-prioritization...
```

### The HITL Flow

```
1. Agent Running
   ↓
2. Agent calls ask_user() or confirm_action()
   ↓
3. AiAgentInteraction record created
   ↓
4. Run status → paused
   ↓
5. User sees modal/question
   ↓
6. User responds
   ↓
7. Response stored in AiAgentInteraction
   ↓
8. AgentRunJob resumes
   ↓
9. LLM receives answer and continues
```

### Example: Multi-Turn HITL

```
User: "Organize my shopping list by priority"
  ↓
Agent: "Found 28 items. Group by category first?"
  → User: "Yes, group by: produce, dairy, frozen, other"
  ↓
Agent: "Created 4 groups. Prioritize the most urgent items?"
  → User: "Yes, these 8 are urgent: [list]"
  ↓
Agent: "Confirmed. 8 items moved to 'High', rest to 'Medium'"
  ↓
Agent Complete! ✓
```

---

## Real-World Examples

### Example 1: Task Breakdown Agent (Manual)

**Scenario:** You need to plan a product launch

**In the UI:**
```
1. Create new list: "Q2 Product Launch"
2. Click [Agents] → [Task Breakdown]
3. Answer questions:
   - "What is your main goal?"
     → "Launch new dashboard feature by June 30"
   - "What's the deadline?"
     → "June 30, 2024"
4. Watch agent work...
5. Results:
   ✅ 24 items created across 5 phases:
      - Phase 1: Discovery (4 items)
      - Phase 2: Design (6 items)
      - Phase 3: Development (8 items)
      - Phase 4: Testing (4 items)
      - Phase 5: Launch (2 items)
```

**In Chat:**
```
You: "Break down the Q2 product launch into tasks.
      We need to launch by June 30."

System: 🤖 Detected agent work. Use Task Breakdown Agent?
You: Yes

Agent: ❓ What is your main goal?
You: Launch new dashboard feature
Agent: ❓ Deadline?
You: June 30, 2024

Agent: 🔄 Running...
[Progress bars showing agent work]

Agent: ✅ Complete!
       Created 24 items in "Q2 Product Launch"
       Organized into 5 phases with priorities
       [View in list] [Refine] [Share]
```

---

### Example 2: Status Report Agent (Scheduled)

**Scenario:** Weekly summary of all your lists

**Configuration:**
```
Agent: Status Report Agent
Trigger: Scheduled (every Monday 9:00 AM)
Scope: All org lists (read-only)
Body Context: all_lists
```

**What happens:**
```
Every Monday at 9:00 AM:
  → AgentScheduleJob detects cron match
  → Status Report Agent auto-runs
  → Analyzes all lists in your organization
  → Generates executive summary:
     • Total items: 127
     • Completed this week: 34
     • Overdue: 3
     • By priority: High (15), Medium (45), Low (67)
  → Sends notification with summary
  → Results saved to run history
```

**User Experience:**
- No action needed
- Automatic notification on Monday mornings
- Can view full report in agent history
- Helps stay informed without checking manually

---

### Example 3: List Organizer Agent (Event-Triggered)

**Scenario:** Auto-reorganize when items complete

**Configuration:**
```
Agent: List Organizer Agent
Trigger: Event (list_item.completed)
Resources: Lists (read/write), Items (read/write), User interaction
```

**Workflow:**
```
User marks an item "Done"
  ↓
Event: list_item.completed fires
  ↓
List Organizer Agent auto-runs
  ↓
Agent analyzes list and asks:
"I found 3 items that can now be prioritized differently.
 Should I reorganize?"
  ↓
User sees modal with options: [Yes] [No] [Review]
  ↓
User clicks [Yes]
  ↓
Agent reorganizes, updating priorities and grouping
  ↓
Items updated in real-time via Turbo Streams
  ✓ Done! List optimized
```

---

### Example 4: Research Agent (Manual + Web Search)

**Scenario:** Enrich items with research

**Configuration:**
```
Agent: Research Agent
Trigger: Manual
Resources: Lists (read/write), Web search
```

**In the UI:**
```
1. Select items in "Reading List"
2. Click [Run Agent] → [Research Agent]
3. Answer: "How deep should I research? (quick/detailed)"
   → Select: detailed

Agent analyzes each item:
  • "Atomic Habits" by James Clear
    → Searches for: author bio, book ratings, key insights
    → Adds to item description:
       - 4.7★ rating on Goodreads
       - Focus: behavior change & habit formation
       - Key insight: "1% improvement compounds"

  • "Deep Work" by Cal Newport
    → Similar research added
    → Related items suggested

Results: 12 items enriched with research data ✓
```

---

## Best Practices

### Creating Effective Agents

**1. Clear Persona**
✅ GOOD: "You are a GTD (Getting Things Done) expert specializing in task prioritization"
❌ BAD: "Be helpful"

**2. Specific Instructions**
✅ GOOD: Step-by-step SOP with clear decision points
❌ BAD: Vague or ambiguous instructions

**3. Appropriate Context**
✅ GOOD: Load only what the agent needs (invocable list, recent runs)
❌ BAD: Load all org data when not needed (slow, expensive)

**4. Meaningful Pre-Run Questions**
✅ GOOD: Ask for parameters that change agent behavior significantly
❌ BAD: Ask for information you already have or don't need

**5. Token Budget**
✅ GOOD: Set realistic budgets based on agent complexity (2-4k per run)
❌ BAD: Set too low (fails) or too high (expensive)

### Using Agents Effectively

**For Automation:**
- Use event-triggered agents for routine work (reorganization, cleanup)
- Use scheduled agents for recurring reports
- Keep HITL agents interactive for complex decisions

**For Ad-Hoc Work:**
- Use manual agents for one-time tasks (research, planning)
- Leverage pre-run questions to personalize results
- Review agent results before major changes

**For Accuracy:**
- Test agents on small datasets first
- Use HITL (confirm_action) before destructive operations
- Monitor token usage and adjust budgets

---

## Common Patterns

### Pattern 1: Ask → Confirm → Execute
```
1. Agent asks clarifying questions (ask_user)
2. Agent shows preview of changes
3. Agent requests confirmation (confirm_action)
4. Agent executes if approved
```
**Use case:** Deletion, reorganization, bulk updates

### Pattern 2: Analyze → Suggest → Apply
```
1. Agent analyzes current state
2. Agent suggests changes
3. User approves/modifies suggestions
4. Agent applies approved changes
```
**Use case:** Optimization, priority changes

### Pattern 3: Generate → Refine → Export
```
1. Agent generates first draft
2. User provides feedback
3. Agent refines based on feedback
4. User exports results
```
**Use case:** Content generation, planning

---

## Troubleshooting

| Problem | Diagnosis | Solution |
|---------|-----------|----------|
| Agent doesn't run | `status != active` or permission denied | Activate agent, verify user access |
| Takes too long | Complex instructions, large context, many tools | Simplify instructions, reduce context, set timeout |
| Produces wrong results | Unclear instructions, wrong context loaded | Clarify instructions, add examples, adjust context |
| Token budget exceeded | Too many tokens per run | Lower max_tokens_per_run, simplify task |
| Event agent not firing | Event subscription not active | Check event_subscriptions.rb, verify trigger_config |
| HITL not pausing | Agent not calling ask_user/confirm_action | Update agent instructions to use HITL |
| Scheduled agent missing | Cron syntax error | Verify cron expression (use crontab.guru) |

---

## Visual Diagrams Reference

- **Architecture Diagram** (`architecture.svg`) — Component overview and execution flow
- **Lifecycle Diagram** (`lifecycle.svg`) — Run states and status transitions
- **Chat Integration** (`chat-integration.svg`) — How chat detects and invokes agents
- **UI Usage** (`ui-usage.svg`) — Where to access agents in the web interface
- **Trigger Types** (`triggers.svg`) — Manual, event-based, and scheduled triggers
- **HITL Flow** (`hitl-flow.svg`) — Human-in-the-loop pausing and resuming

---

## Next Steps

1. **Explore the Agent Library** — Visit `/agents` to see available agents
2. **Try a Manual Agent** — Run Task Breakdown on a new list
3. **Create Custom Agent** — Go to `/agents/new` and create an org-specific agent
4. **Set Up Events** — Configure an event-triggered agent for automation
5. **Review History** — Check agent run history to understand what happened

---

## Additional Resources

- **Complete Reference:** See [AGENTS.md](../AGENTS.md) for technical details
- **Database Schema:** AI Agent models and relationships
- **API Documentation:** Agent trigger and execution endpoints
- **Code Examples:** See `db/seeds.rb` for 4 seeded system agents

---

**Last Updated:** 2026-03-25
**Status:** Complete & Visual
**All Diagrams:** SVG format for clarity and performance