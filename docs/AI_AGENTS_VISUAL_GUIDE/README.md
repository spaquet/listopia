# AI Agents Visual Guide

Welcome to the comprehensive visual guide for Listopia's AI Agent system! This folder contains detailed documentation with SVG diagrams explaining how AI agents work, how to use them, and real-world examples.

## 📚 Contents

### Main Documentation
- **[index.md](./index.md)** — Complete guide with all explanations and examples
  - Quick overview of what agents do
  - How the system works architecturally
  - How to use agents from chat
  - How to use agents from the UI
  - Agent lifecycle and execution
  - Three trigger types (manual, event, scheduled)
  - Human-in-the-loop interactions
  - Real-world examples and best practices

### Visual Diagrams (SVG Format)

All diagrams are interactive SVG files that can be viewed in any browser:

1. **[architecture.svg](./architecture.svg)**
   - System components (trigger, config, execution engine, tools, memory)
   - How each component connects
   - Overall execution flow
   - **Key insight:** Shows how agents work at a high level

2. **[lifecycle.svg](./lifecycle.svg)**
   - Complete run lifecycle from trigger to completion
   - All possible states (pending, awaiting_input, running, paused, completed, failed, cancelled)
   - What happens at each stage
   - **Key insight:** Understand what's happening during execution

3. **[chat-integration.svg](./chat-integration.svg)**
   - Chat interface showing natural language invocation
   - Backend processing pipeline (intent detection → agent matching → execution)
   - Real-time progress updates
   - **Key insight:** How chat discovers and invokes agents automatically

4. **[ui-usage.svg](./ui-usage.svg)**
   - Agent library browsing interface
   - Agent details page with run controls
   - How to access agents from lists
   - Quick agent menu and configuration
   - **Key insight:** All ways to interact with agents in the UI

5. **[triggers.svg](./triggers.svg)**
   - Three trigger types side-by-side: Manual, Event-Based, Scheduled
   - Detailed flow for each trigger type
   - Comparison table
   - **Key insight:** When and how to use each trigger type

6. **[hitl-flow.svg](./hitl-flow.svg)**
   - Human-in-the-loop interaction flow
   - What happens when agent pauses for user input
   - Real example scenario (shopping list organizer)
   - **Key insight:** How agents pause and wait for user decisions

## 🎯 How to Use This Guide

### I want to understand...

**...what AI agents are:**
1. Read the "Quick Overview" in [index.md](./index.md)
2. View [architecture.svg](./architecture.svg)

**...how to use agents from chat:**
1. Read "Using Agents from Chat" section
2. View [chat-integration.svg](./chat-integration.svg)
3. Check Example 1 in Real-World Examples

**...how to use agents from the UI:**
1. Read "Using Agents from the UI" section
2. View [ui-usage.svg](./ui-usage.svg)
3. Try navigating to `/agents` in your app

**...how agents execute:**
1. Read "Agent Lifecycle & Execution"
2. View [lifecycle.svg](./lifecycle.svg)
3. Check "Step-by-Step: Invoking an Agent from Chat"

**...how to trigger agents automatically:**
1. Read "Trigger Types" section
2. View [triggers.svg](./triggers.svg)
3. Read Examples 2 & 3 in Real-World Examples

**...how human-in-the-loop works:**
1. Read "Human-in-the-Loop" section
2. View [hitl-flow.svg](./hitl-flow.svg)
3. Check the example scenario

## 📋 Key Concepts

### Five Configuration Fields
Every agent is defined by:
1. **Persona** — Who the agent is (role, tone)
2. **Instructions** — What the agent does (step-by-step)
3. **Body Context** — What context to auto-load
4. **Pre-Run Questions** — What to ask before execution
5. **Trigger Config** — How it gets invoked (manual/event/scheduled)

### Three Trigger Types
- **Manual** — User clicks "Run Agent"
- **Event-Based** — Triggered when app events occur (e.g., item completed)
- **Scheduled** — Runs on a cron schedule (e.g., every Monday 9am)

### Execution Flow
```
Trigger → Create Run → Check Questions → Build Context → Execute Loop → Complete
```

### Human-in-the-Loop (HITL)
- `ask_user()` — Ask a question, wait for response
- `confirm_action()` — Request approval before action
- Agent pauses → User responds → Agent resumes

## 🚀 Quick Start Examples

### Example 1: Run Task Breakdown from Chat
```
You: "Break down the Q1 roadshow into tasks"
System detects agent work
Agent runs and creates 12 tasks
```

### Example 2: Auto-Organize on Item Completion
```
You mark item done
List Organizer Agent auto-runs
Agent reorganizes list
Notification sent
```

### Example 3: Weekly Status Report
```
Every Monday 9am (automatic)
Status Report Agent runs
Executive summary sent
No action needed
```

## 💡 Best Practices

**Creating Agents:**
- Be specific with persona and instructions
- Load only needed context
- Ask for parameters that matter
- Set realistic token budgets

**Using Agents:**
- Test on small datasets first
- Use HITL for important decisions
- Monitor execution history
- Adjust based on results

## 🔗 Related Documents

- **[AGENTS.md](../AGENTS.md)** — Complete technical reference
- **[CLAUDE.md](../../CLAUDE.md)** — Project-wide guidelines
- **Codebase:**
  - `app/models/ai_agent.rb` — Agent model
  - `app/services/agent_execution_service.rb` — Execution logic
  - `app/jobs/agent_run_job.rb` — Background job
  - `db/seeds.rb` — 4 seeded system agents

## ❓ FAQ

**Q: Can I create my own agents?**
A: Yes! Go to `/agents/new` to create org-specific or personal agents.

**Q: Do agents cost money?**
A: Agents use tokens which are part of your LLM API usage. Set budgets to control costs.

**Q: Can multiple agents run at the same time?**
A: Yes, but they execute independently. Each agent is a separate run.

**Q: What happens if an agent fails?**
A: The run is marked as failed. You can view the error log and retry.

**Q: How do I stop a running agent?**
A: Click [Cancel] on the run page. Partial results are saved.

## 📞 Support

- Check [Troubleshooting](./index.md#troubleshooting) section for common issues
- Review Examples section for real-world scenarios
- Check agent run history for detailed logs
- Consult [AGENTS.md](../AGENTS.md) for technical details

---

**Status:** Complete & Production-Ready
**Last Updated:** 2026-03-25
**Format:** Markdown + SVG Diagrams
**Version:** 1.0