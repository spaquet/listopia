# AI Agents Quick Reference Card

Quick answers to common questions. For detailed explanations, see [index.md](./index.md).

---

## 🎯 What Can Agents Do?

✅ Break down complex goals into actionable tasks
✅ Generate reports across all lists
✅ Reorganize and optimize lists
✅ Research and enrich items
✅ Run automatically on schedule
✅ Respond to app events instantly
✅ Ask clarifying questions before running
✅ Request approval before major actions

---

## 🚀 How to Run an Agent

### From Chat
```
You: "Break down the Q1 roadshow planning"
System suggests → Task Breakdown Agent
Agent answers questions → Creates 24 tasks
```

### From Agent Library
```
1. Go to /agents
2. Find agent (e.g., "Task Breakdown Agent")
3. Click [Run Agent]
4. Answer pre-run questions
5. Watch progress and results
```

### From List View
```
1. Open any list
2. Click [More] menu
3. Select [Run Agent]
4. Choose agent from list
5. Agent runs on this list
```

---

## ⚙️ Core Configuration

### Every Agent Has 5 Required Fields

| Field | Purpose | Example |
|-------|---------|---------|
| **Persona** | WHO is the agent? | "Senior project manager expert at decomposition" |
| **Instructions** | WHAT does it do? | "1. Understand goal 2. Identify phases 3. Create tasks 4. Ask approval" |
| **Body Context** | WHAT context to load? | "invocable" (current list) or "all_lists" or "recent_runs" |
| **Pre-Run Questions** | WHAT to ask first? | "What is your main goal?" |
| **Trigger Config** | HOW to invoke? | "manual" or "event" or "schedule" |

---

## 🔄 Three Trigger Types

### 1️⃣ MANUAL (User-Initiated)
```json
{ "type": "manual" }
```
- User clicks [Run Agent]
- Immediate execution
- **Use for:** Ad-hoc requests, one-time tasks

### 2️⃣ EVENT-TRIGGERED (Automatic)
```json
{
  "type": "event",
  "event_type": "list_item.completed"
}
```
- Fires when app event occurs
- No user action needed
- **Use for:** Auto-organization, cleanup

**Available events:**
- `list_item.created`
- `list_item.updated`
- `list_item.completed`
- `list_item.assigned`

### 3️⃣ SCHEDULED (Recurring)
```json
{
  "type": "schedule",
  "cron": "0 9 * * 1"
}
```
- Runs at specified times (cron syntax)
- Fully automated
- **Use for:** Recurring reports, weekly digests

**Cron examples:**
- `0 9 * * 1` → Monday 9am
- `0 9 * * 1-5` → Weekdays 9am
- `*/15 * * * *` → Every 15 minutes
- `0 0 1 * *` → 1st of month midnight

---

## 🎓 Agent Lifecycle (6 Steps)

```
1. TRIGGER
   ↓ Manual click / Event / Scheduled time
2. CREATE RUN
   ↓ AiAgentRun created (pending)
3. CHECK QUESTIONS
   ↓ If pre-run questions exist → ask user (awaiting_input)
4. BUILD CONTEXT
   ↓ Compose system prompt with persona + instructions + context
5. EXECUTE LOOP
   ↓ LLM generates reasoning, calls tools, receives results
6. COMPLETE
   ↓ Save results, notify user, emit events
```

**Status flow:**
```
pending → awaiting_input → running → (paused?) → completed/failed/cancelled
```

---

## 🤝 Human-in-the-Loop (HITL)

Agents can pause and ask questions:

### Two HITL Tools

**ask_user(question, options[])**
```
Agent: "Found 5 duplicates. What should I do?"
Options: ["Delete", "Keep", "Review first"]
```

**confirm_action(description, expected_outcome)**
```
Agent: "I'm about to re-prioritize 12 items.
        Do you approve?"
[Confirm] [Cancel]
```

### HITL Flow
```
Agent running
    ↓
Calls ask_user() or confirm_action()
    ↓
Run paused, user sees modal
    ↓
User responds
    ↓
Agent resumes with answer
```

---

## 📊 Configuration Examples

### Task Breakdown Agent
```ruby
AiAgent.create!(
  name: "Task Breakdown",
  persona: "Senior project manager",
  instructions: "1. Understand goal\n2. Identify phases\n3. Create tasks\n4. Ask approval",
  trigger_config: { "type": "manual" },
  body_context_config: { "load": "invocable" },
  pre_run_questions: [
    { "key": "goal", "question": "What is your main goal?", "required": true }
  ]
)
```

### Status Report Agent
```ruby
AiAgent.create!(
  name: "Status Report",
  persona: "Executive assistant",
  trigger_config: { "type": "schedule", "cron": "0 9 * * 1" },
  body_context_config: { "load": "all_lists" },
  pre_run_questions: [] # No questions, fully automated
)
```

### List Organizer Agent
```ruby
AiAgent.create!(
  name: "List Organizer",
  persona: "GTD expert",
  trigger_config: { "type": "event", "event_type": "list_item.completed" },
  body_context_config: { "load": "invocable" }
)
```

---

## 💾 Resources & Permissions

Each agent can access tools based on granted resources:

### Common Resources
- `list` (read / read_write)
- `list_item` (read / read_write)
- `web_search` (available)
- `user_interaction` (expect_response)

### Example: Grant Permissions
```ruby
agent.ai_agent_resources.create!(
  resource_type: "list",
  permission: :read_write
)
agent.ai_agent_resources.create!(
  resource_type: "user_interaction",
  permission: :expect_response
)
```

---

## ⏱️ Token Budgets

Control costs by setting limits:

| Limit | Default | Purpose |
|-------|---------|---------|
| `max_tokens_per_run` | 4,000 | Max tokens for one execution |
| `max_tokens_per_day` | 50,000 | Daily quota |
| `max_tokens_per_month` | 500,000 | Monthly quota |

**Tip:** Monitor token usage in agent run history to optimize costs.

---

## 🔧 Common Troubleshooting

| Problem | Quick Fix |
|---------|-----------|
| Agent won't run | Check `status: active` in settings |
| Takes too long | Simplify instructions, reduce context, set timeout |
| Wrong results | Clarify instructions, add examples |
| Too many tokens | Lower max_tokens_per_run |
| Event agent silent | Verify event subscription is active |
| HITL not working | Ensure agent instructions call ask_user() |
| Scheduled agent missing | Check cron syntax at crontab.guru |

---

## 📋 Agent Execution States

```
┌─────────────────────────────────────┐
│          Agent Run States           │
├─────────────────────────────────────┤
│ pending         → Waiting to start  │
│ awaiting_input  → Waiting for user  │
│ running         → Actively executing│
│ paused          → HITL (user input) │
│ completed       → ✓ Finished        │
│ failed          → ✗ Error occurred  │
│ cancelled       → ⊘ User stopped    │
└─────────────────────────────────────┘
```

---

## 🎯 Best Practices Checklist

### Creating Agents
- [ ] Clear, specific persona
- [ ] Step-by-step instructions
- [ ] Only load needed context
- [ ] Ask for important parameters
- [ ] Set realistic token budgets
- [ ] Test with small data first

### Using Agents
- [ ] Understand what agent does
- [ ] Answer pre-run questions accurately
- [ ] Review pre-execution preview
- [ ] Approve HITL questions
- [ ] Monitor token usage
- [ ] Rate agent after running
- [ ] Save useful results

---

## 🚦 Decision Tree

**What trigger type should I use?**

```
Does user initiate?
├─ YES → Manual trigger
└─ NO → Does it respond to events?
        ├─ YES → Event trigger
        └─ NO → Scheduled trigger
```

**Should I use HITL?**

```
Is this a significant change?
├─ YES (deletion, reorganization) → Use confirm_action()
├─ MAYBE (ambiguous intent) → Use ask_user()
└─ NO (simple action) → No HITL needed
```

**What context to load?**

```
Does agent need:
├─ Current list/item? → invocable
├─ All org lists? → all_lists
├─ Prior runs? → recent_runs
└─ Multiple? → all of the above
```

---

## 📞 Need More Help?

- **Detailed Guide:** See [index.md](./index.md)
- **Visual Diagrams:** Check the .svg files in this folder
- **Technical Reference:** See [AGENTS.md](../AGENTS.md)
- **Code Examples:** Check `db/seeds.rb` for 4 system agents
- **Troubleshooting:** See index.md#troubleshooting section

---

**Print This Card** → Bookmark for quick reference!

**Last Updated:** 2026-03-25