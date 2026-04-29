# Chat System Flow & Architecture

Complete guide to how user messages flow through Listopia's unified chat system, from input to response.

**Important:** This flow is **domain-agnostic** and works for ANY type of list. The system doesn't hardcode specific domains - it intelligently adapts to whatever the user is planning (events, courses, recipes, projects, reading lists, etc.).

## Quick Summary

**Single Unified Chat Interface** - Handles everything from general questions to list creation to resource management, for any domain.

**Key Flows:**
1. **Simple Requests** → Agent executes directly (1-2s total)
   - Examples: Quick grocery list, simple task list
2. **Complex Requests** → Agent asks clarifying questions (HITL) → User answers → Agent generates items (10-15s total)
   - LLM intelligently detects best subdivision type (locations, books, modules, phases, topics, etc.)
   - ItemGenerationService generates items specific to each subdivision
   - Examples: Roadshow with locations, reading list with books, course with modules
3. **Commands** → Command-specific agent executes synchronously (0.5s)
4. **Navigation** → NavigationAgent routes to page (0.3s)
5. **Resource Creation** → ResourceCreationAgent collects parameters → Creates resource

**Agent-Centric Orchestration:**
- Intent detection is **fast** (CombinedIntentComplexityService, <2s)
- Execution is **agent-based** (ListCreationAgent, ResourceCreationAgent, etc.)
- State is **agent run history** (no separate ChatContext model)
- Audit trail is **automatic** (every agent run is recorded)

**Key Innovation (2026-03-21):** Subdivision detection and item generation are fully generic. The system uses LLM to determine the best way to organize ANY list, then generates appropriate items. See [ITEM_GENERATION.md](ITEM_GENERATION.md) for details.

---

## Complete Message Flow Diagram

```
┌──────────────────────────────────────────────────────────────┐
│ User Types Message in Chat                                    │
└────────────┬─────────────────────────────────────────────────┘
             │
             ▼
┌──────────────────────────────────────────────────────────────┐
│ ChatsController#create_message (Sync)                        │
├──────────────────────────────────────────────────────────────┤
│ 1. Prompt injection detection                                │
│ 2. Content moderation check                                  │
│ 3. Save message to database                                  │
│ 4. Parse @mentions and #references                           │
│ 5. Detect if command (/search, /help, etc)                  │
└────────────┬─────────────────────────────────────────────────┘
             │
    ┌────────┴────────┐
    │                 │
    ▼ COMMAND         ▼ LLM MESSAGE
    │                 │
    │ Sync            │ Async (ProcessChatMessageJob)
    │ Execution       │
    │                 ▼
    │        ┌──────────────────────────────────┐
    │        │ [PHASE 1] Fast Intent Detection  │
    │        │ CombinedIntentComplexityService  │
    │        │ (service, <2s)                   │
    │        ├──────────────────────────────────┤
    │        │ Output:                          │
    │        │  - intent                        │
    │        │  - is_complex flag               │
    │        │  - parameters                    │
    │        │  - planning_domain               │
    │        └────────────┬─────────────────────┘
    │                     │
    │        ┌────────────▼──────────────────────────┐
    │        │ [PHASE 2] Route to Specialized Agent │
    │        │ Based on: intent + complexity        │
    │        ├──────────────────────────────────────┤
    │        │ Possible agents:                     │
    │        │  - ListCreationAgent                 │
    │        │  - ResourceCreationAgent             │
    │        │  - SearchAgent                       │
    │        │  - NavigationAgent                   │
    │        │  - GeneralQAAgent                    │
    │        └────────────┬─────────────────────────┘
    │                     │
    │     ┌───────────────┼───────────────┬──────────┬────────────┐
    │     │               │               │          │            │
    │     ▼ LIST          ▼ RESOURCE      ▼ SEARCH   ▼ NAVIGATE   ▼ GENERAL
    │     │               │               │          │            │
    │     │               │               │          │            ▼
    │     │               │               │          │     GeneralQAAgent
    │     │               │               │          │     (LLM + tools)
    │     │               │               │          │
    │     │               │               │          ▼
    │     │               │               │     NavigationAgent
    │     │               │               │     (Route to page)
    │     │               │               │
    │     │               │               ▼
    │     │               │          SearchAgent
    │     │               │          (Execute search)
    │     │               │
    │     │               ▼
    │     │        ResourceCreationAgent
    │     │        ├─ Ask missing params (HITL)
    │     │        ├─ Create resource
    │     │        └─ Send invites/confirmations
    │     │
    │     ▼
    │  ListCreationAgent
    │  ├─ Check: is_complex?
    │  │
    │  ├─ YES → Ask pre-run questions (HITL)
    │  │        Message type: planning_form
    │  │        User answers →
    │  │        Extract parameters →
    │  │        Generate items (ItemGenerationService) →
    │  │        Create list →
    │  │        Message type: list_created
    │  │
    │  └─ NO → Create list immediately
    │           Message type: list_created
    │
    │        [PHASE 3] Agent Execution Loop
    │        ├─ Load agent config + body_context
    │        ├─ Build system prompt
    │        ├─ LLM call with tools
    │        ├─ Tool execution + results
    │        ├─ Real-time progress updates
    │        │  Message type: progress_indicator OR agent_running
    │        ├─ HITL interactions if needed
    │        │  Message type: agent_paused
    │        └─ Completion
    │           Message type: (determined by result)
    │
    │        [PHASE 4] Broadcast Result
    └────────────────────────────────┐
                                    │
                    ┌───────────────▼──────────────┐
                    │ Turbo Stream Broadcast        │
                    │ - Message type: [list_created │
                    │   search_results, nav, etc]   │
                    │ - Agent run ID (audit trail)  │
                    │ - Metadata                    │
                    └───────────────┬───────────────┘
                                    │
                    ┌───────────────▼──────────────┐
                    │ Frontend Renders by Type     │
                    │ (see MESSAGE_TYPES.md)       │
                    │ - Text                       │
                    │ - Planning form              │
                    │ - List created               │
                    │ - Progress indicator         │
                    │ - Navigation                 │
                    │ - Search results             │
                    │ - Agent running/paused       │
                    └──────────────────────────────┘
```

---

## Intent Types & Agent Routing

### What is Intent?

Intent is the **user's goal** - what they're trying to accomplish. The system detects this automatically via **CombinedIntentComplexityService** and routes to the appropriate **AI Agent** for execution.

### Intent Types → Agent Mapping

| Intent | Agent | Processing | Example |
|--------|-------|------------|---------|
| **create_list** | ListCreationAgent | Check complexity → Ask questions (HITL) or create immediately | "Plan my roadshow" |
| **create_resource** | ResourceCreationAgent | Collect missing params (HITL) → Create resource → Send invites | "Add user john@example.com" |
| **navigate_to_page** | NavigationAgent | Detect route → Broadcast navigation message | "Show users list" |
| **manage_resource** | ResourceManagementAgent | Update/delete existing resource | "Archive the budget list" |
| **search_data** | SearchAgent | Execute search → Format results → Broadcast | "Find lists about budget" |
| **general_question** | GeneralQAAgent | Call LLM with available tools → Respond | "How do I use tags?" |

### Agent Execution Model

**All agents follow this pattern:**

```
1. Agent Triggered
   ├─ Manual: User clicks "Run"
   ├─ From Chat: Intent detected → Agent invoked
   └─ Event-based/Scheduled: Automatic

2. Pre-Run Questions (if configured)
   ├─ Agent has pre_run_questions
   ├─ Run status → awaiting_input
   ├─ Message type: planning_form (HITL)
   ├─ User answers → stored in AiAgentRun
   └─ AgentRunJob enqueued

3. Build Execution Context
   ├─ Load agent config (persona, instructions)
   ├─ Load body_context (invocable list, all lists, etc.)
   ├─ Compose system prompt
   └─ Include user input + pre_run_answers

4. LLM Execution Loop
   ├─ Call LLM with tools
   ├─ Tool execution (CRUD, search, HITL, etc.)
   ├─ Real-time progress updates (Turbo Streams)
   ├─ Message type: progress_indicator or agent_running
   └─ Loop until complete

5. HITL Interactions
   ├─ If agent calls ask_user or confirm_action
   ├─ Run status → paused
   ├─ Message type: agent_paused
   ├─ AiAgentInteraction created
   ├─ User responds
   └─ Agent resumes

6. Completion
   ├─ Run status → completed
   ├─ Emit: agent_run.completed event
   ├─ Determine message type based on output
   ├─ Broadcast to chat
   └─ Ready for follow-up
```

---

## State Machine: Conversation States

The chat maintains state to handle multi-turn conversations:

```
┌──────────────────────────────────────────────────────┐
│ Normal Conversation (no pending state)               │
└────────────────────┬─────────────────────────────────┘
                     │
         ┌───────────┼───────────┐
         │           │           │
         ▼           ▼           ▼
    ┌─────────┐ ┌─────────┐ ┌──────────────┐
    │ Create  │ │Navigate │ │General Q/A   │
    │ list    │ │ to page │ │ (LLM tools)  │
    └────┬────┘ └────┬────┘ └──────┬───────┘
         │           │             │
         ▼           │             │
    ┌──────────────────┐           │
    │ Complex?         │           │
    └─┬──────────────┬─┘           │
      │              │             │
      ▼ YES          ▼ NO          │
    ┌──────────────────┐           │
    │PENDING:PRE-      │     ┌─────┴────────┐
    │CREATION_         │     │Create list   │
    │PLANNING          │     │immediately   │
    │                  │     └──────┬───────┘
    │Show questions    │            │
    │Await answers     │            │
    └────────┬─────────┘            │
             │                      │
      ┌──────▼──────────┐           │
      │User responds    │           │
      │to questions     │           │
      └────────┬────────┘           │
               │                    │
        ┌──────▼──────────────────┐ │
        │Create enriched list     │ │
        │with refinements         │ │
        └──────┬──────────────────┘ │
               │                    │
               └────────┬───────────┘
                        │
                  ┌─────▼────────────┐
                  │Response sent     │
                  │Chat returns to   │
                  │normal state      │
                  └──────────────────┘
```

### State Management in ChatContext AR Model

**ChatContext tracks conversation state persistently:**

```ruby
# When in pre_creation state (waiting for answers)
chat_context = {
  state: "pre_creation",
  status: "awaiting_user_input",
  pre_creation_questions: [...],
  pre_creation_answers: {},  # Populated as user answers
  parameters: { title: "...", category: "..." }
}

# When in resource_creation state (creating list)
chat_context = {
  state: "resource_creation",
  status: "processing",
  parameters: { title: "...", items: [...] },
  hierarchical_items: { parent_items: [...], subdivisions: {...} },
  generated_items: [...]
}

# When completed (list created)
chat_context = {
  state: "completed",
  status: "complete",
  list_created_id: "uuid",
  post_creation_mode: true  # Ask user: keep or clear context?
}
```

---

## Detailed Flow by Scenario

### Scenario 1: Simple List Creation

**User Input:** "Create a grocery list"

```
Step 1: [SYNC] Intent Detection
  Service: CombinedIntentComplexityService
  Model: gpt-4.1-nano
  Time: ~2 seconds
  Result: {
    intent: "create_list",
    is_complex: false,              ← KEY: Not complex
    parameters: {
      title: "grocery list",
      category: needs_clarification
    }
  }

Step 2: Route to Agent
  Agent: ListCreationAgent
  Trigger: Manual (from chat)
  Pre-run questions: None (not configured for simple lists)
  Status: pending → in_progress

Step 3: Agent Execution (Background Job)
  Load body_context: invocable (current list)
  Persona: "You are a helpful assistant for list management"
  Instructions: "1. Understand the request. 2. Check if category needed. 3. Create list. 4. Respond."

Step 4: Ask Category (HITL)
  Agent calls: ask_user("What category?", ["Personal", "Professional"])
  Message type: agent_paused (HITL)
  User clicks: "Personal"
  AiAgentInteraction marked answered
  Agent resumes with answer

Step 5: Create List
  Agent calls: create_list_item(title: "grocery list", category: "personal")
  List created in database
  Agent continues reasoning

Step 6: Response
  Agent generates final output
  Status: completed
  Message type: list_created
  Broadcast via Turbo Stream: "I've created your grocery list. You can start adding items!"

Total Time: ~2-3 seconds perceived ✅
(+1-2 seconds if user sees category question)
```

---

### Scenario 2: Complex List with Pre-Run Questions

**User Input:** "Help me plan a roadshow across the US"

```
Step 1: [SYNC] Intent Detection
  Service: CombinedIntentComplexityService
  Model: gpt-4.1-nano
  Time: ~2 seconds
  Result: {
    intent: "create_list",
    is_complex: true,               ← KEY: Detected as complex
    complexity_indicators: [
      "multi_location",
      "time_bound",
      "coordination"
    ],
    planning_domain: "event",
    parameters: {
      title: "US Roadshow",
      category: "professional"
    }
  }

Step 2: Route to Agent
  Agent: ListCreationAgent
  Config has pre_run_questions: [
    { key: "locations", question: "Which cities will you visit?", required: true },
    { key: "timeline", question: "What's the timeline?", required: true },
    { key: "budget", question: "What's your budget?", required: true }
  ]
  Status: pending → awaiting_input

Step 3: Show Pre-Run Questions Form
  Message type: planning_form
  User sees form immediately (~100ms)
  Form broadcasts via Turbo Stream

Step 4: User Provides Answers
  "Locations: NYC, LA, Chicago, SF, Seattle
   Timeline: June - September 2026
   Budget: $500,000"

Step 5: Process Answers & Trigger Agent
  POST /chats/:id/answer_pre_run_questions
  Answers stored in: AiAgentRun#pre_run_answers
  Status: awaiting_input → in_progress
  AgentRunJob enqueued

Step 6: [ASYNC] Agent Executes (Background)
  Load agent config:
    ├─ Persona: "Senior event planner"
    ├─ Instructions: "Break down roadshow into location-specific tasks"
    ├─ Body context: Invocable list
    └─ Tools: create_list_item, invoke_item_generation_service

  Build system prompt:
    - Persona + instructions
    - User input: "Plan US roadshow"
    - Pre-run answers: locations, timeline, budget
    - Available tools

Step 7: Agent Reasoning Phase
  LLM processes:
    1. Understand the request with provided parameters
    2. Determine subdivision type: :locations
    3. Extract: ["New York", "Los Angeles", "Chicago", "San Francisco", "Seattle"]
    4. Plan approach: Create main list + 5 sublists

Step 8: Real-Time Progress Updates
  Message type: progress_indicator
  As agent works, Turbo Streams push updates:
    - "Creating main list..."
    - "Generating items for New York..."
    - "Generating items for Chicago..."
    etc.

Step 9: Generate Items for Each Location
  Agent calls tool: invoke_item_generation_service
    Input:
      - List title: "roadshow for Listopia"
      - Sublist title: "New York"
      - Planning context: {locations: [...], budget, timeline}
      - Category: "professional"
    Output: 5-8 location-specific items
      ├─ Confirm venue booking at Times Square
      ├─ Arrange local transportation
      ├─ Coordinate with NY vendors
      ├─ Plan media outreach
      ├─ Setup accommodations
      └─ Arrange AV equipment

  Repeats for: LA, Chicago, SF, Seattle
  (5 calls × 2-3s each ≈ 10-15 seconds)

Step 10: Create List Structure
  Agent calls tools:
    create_list(title: "roadshow for Listopia")
    create_list_item(...) for each location
    create_list_item(...) for each task in each location

  Result: Hierarchical structure
    List: "roadshow for Listopia"
    ├─ Sublist: "New York" [6 items]
    ├─ Sublist: "Los Angeles" [5 items]
    ├─ Sublist: "Chicago" [5 items]
    ├─ Sublist: "San Francisco" [4 items]
    └─ Sublist: "Seattle" [4 items]
    Total: 28 items

Step 11: Agent Completion
  Status: in_progress → completed
  Emit: agent_run.completed event
  Output: {
    list_id: uuid,
    items_created: 28,
    structure: hierarchical
  }

Step 12: Broadcast Response
  Message type: list_created
  Via Turbo Stream:
    ✅ Created roadshow plan across 5 cities
    - New York: 6 items
    - Los Angeles: 5 items
    - Chicago: 5 items
    - San Francisco: 4 items
    - Seattle: 4 items
    Total: 28 items

    Timeline: June - September 2026
    Budget: $500,000

    [View list] [Refine] [Share]

Total Time:
  - Question display: ~100ms perceived
  - Agent execution: ~15-20 seconds
    ├─ Reasoning: 1-2s
    ├─ Item generation: 10-15s
    ├─ List creation: 2-3s
  - Total user perceived: Form → 20s → List appears ✅
```

---

### Scenario 3: Navigation Intent

**User Input:** "Show me the users list"

```
Step 1: [SYNC] Intent Detection
  Service: CombinedIntentComplexityService
  Result: {
    intent: "navigate_to_page",     ← KEY: Navigation
    path: "admin_users"
  }

Step 2: Route to Agent
  Agent: NavigationAgent
  Trigger: Immediate (synchronous)

Step 3: Agent Execution
  Agent reasoning: "User wants to navigate to users page"
  Agent calls tool: navigate_to_page(path: "/admin/users")
  Status: completed
  Output: { path: "/admin/users" }

Step 4: Broadcast Navigation Message
  Message type: navigation
  Data: { path: "/admin/users", target: "_self" }

Step 5: Frontend Navigation
  JavaScript detects message type="navigation"
  Triggers: Turbo.visit("/admin/users")

Step 6: Page Loads
  User sees users page

Total Time: ~0.5 seconds ✅
```

---

### Scenario 4: Command Processing

**User Input:** "/search budget"

```
Step 1: [SYNC] Controller Detects Command
  File: ChatsController#create_message
  Message starts with "/" → Command processing (synchronous)

Step 2: Route to Command Agent
  Command: "search"
  Agent: SearchAgent
  Trigger: Synchronous (no background job)

Step 3: Agent Executes Command
  Parse command: /search budget
  Query: "budget"
  Execute search: SearchService.search("budget", user.organization)
  Results: 3 lists matching "budget"

Step 4: Broadcast Results
  Message type: command_response or search_results
  Data: {
    query: "budget",
    result_count: 3,
    results: [...]
  }

Step 5: Frontend Displays Results
  Message rendered immediately
  User can click to navigate to results

Total Time: ~0.5 seconds ✅ (Synchronous)
```

---

### Scenario 5: Resource Creation (User)

**User Input:** "Create a user for john@example.com"

```
Step 1: [SYNC] Intent Detection
  Service: CombinedIntentComplexityService
  Result: {
    intent: "create_resource",
    resource_type: "user",
    parameters: {
      email: "john@example.com"
    },
    missing: ["name"]
  }

Step 2: Route to Agent
  Agent: ResourceCreationAgent
  Config has pre_run_questions: [
    { key: "name", question: "What's the user's full name?", required: true }
  ]
  Status: pending → awaiting_input

Step 3: Show Pre-Run Questions
  Message type: planning_form
  Question: "What's the user's full name?"
  User enters: "John Smith"

Step 4: Trigger Agent Execution
  POST /chats/:id/answer_pre_run_questions
  Answers stored: { name: "John Smith" }
  Status: awaiting_input → in_progress
  AgentRunJob enqueued

Step 5: Agent Executes
  Load parameters:
    Email: john@example.com
    Name: John Smith
    Role: member (default)

  Agent calls tool: create_user(email, name, role)
  User created in database
  Sends magic link invitation

Step 6: Agent Completion
  Status: completed
  Output: { user_id, email, name }

Step 7: Broadcast Result
  Message type: resource_created
  "Created user John Smith (john@example.com). Invitation sent."
  [View user]

Total Time: ~3-4 seconds (including user input) ✅
```

---

### Scenario 6: General Question (No Intent Match)

**User Input:** "How do I add people to my team?"

```
Step 1: [SYNC] Intent Detection
  Service: CombinedIntentComplexityService
  Result: {
    intent: "general_question"  ← No specific match
  }

Step 2: Route to Agent
  Agent: GeneralQAAgent
  Trigger: Background job (ProcessChatMessageJob)
  Pre-run questions: None

Step 3: Agent Configuration
  Model: gpt-5-mini
  Persona: "You are a helpful assistant for Listopia"
  Instructions: "Answer user questions about features, provide guidance, use available tools if helpful"
  Tools Available:
    - navigate_to_page (routing)
    - list_lists, list_users, list_teams (read)
    - create_list, create_user (create)
    - search
    - And more

Step 4: Agent Executes
  Load body_context: None (general context not needed)
  Build system prompt with tools
  LLM processes: "How do I add people to my team?"

Step 5: LLM Reasoning
  Formulates helpful answer with examples
  May call tools if helpful (e.g., list_teams to show examples)
  Or just provide direct guidance

Step 6: Tool Execution (if called)
  Agent calls tool: list_teams() → Returns user's teams
  Tool result fed back to LLM

Step 7: LLM Synthesizes Answer
  Combines guidance + tool results if any
  Generates response: "You can add people to your team by:
   1. Open your team
   2. Click 'Invite member'
   3. Enter their email
   4. They'll receive a magic link invitation..."

Step 8: Broadcast Response
  Message type: text
  Content: Full response with markdown formatting

Total Time: ~2-3 seconds ✅
```

---

## Model Selection: Why gpt-4.1-nano for Intent Detection?

### The Choice

**CombinedIntentComplexityService uses `gpt-4.1-nano`** for intent + complexity detection

### Why Not gpt-5 or gpt-5-nano?

| Model | Use Case | Latency | Cost | Why (Not) |
|-------|----------|---------|------|-----------|
| gpt-4.1-nano | Classification (CHOSEN) | ~2s | Low | Fast, cheap, sufficient for classification |
| gpt-5-nano | General purpose | ~2-3s | Medium | More capable but slower |
| gpt-5 | Complex reasoning | ~3-4s | Higher | Overkill for simple classification |

### Classification vs Reasoning

Intent detection is **CLASSIFICATION**, not reasoning:

```
INPUT: "Plan my roadshow across US cities"

CLASSIFICATION TASK (gpt-4.1-nano = perfect):
  ├─ Intent? → "create_list"
  ├─ Complex? → true
  ├─ Domain? → "event"
  └─ Confidence? → 0.98

vs REASONING TASK (would waste gpt-5):
  ├─ Why is it complex?
  ├─ What would make it less complex?
  ├─ Are there alternative approaches?
  ├─ What's the user's true underlying need?
  └─ What would they regret after?
```

### Performance Impact

**CombinedIntentComplexityService = 3 services in 1 call:**

Before optimization (3 separate calls):
```
AiIntentRouterService:           1.5s
ListComplexityDetectorService:   0.5s
ParameterExtractionService:      1.0s
────────────────────────────────
Total:                           3.0s ❌
```

After optimization (1 call):
```
CombinedIntentComplexityService: 2.0s ✅
Savings: 1.0s (33% faster)
```

---

## Agent Pre-Run Questions vs Post-Creation Refinement

These are **different phases** in the agent lifecycle:

### Agent Pre-Run Questions
- **When:** Before agent execution starts
- **Why:** Gather context that affects how agent operates
- **Mechanism:** Agent.pre_run_questions configuration
- **HITL Tool:** ask_user() in agent
- **Speed:** <1 second to show form
- **Questions:** 3-5 specific questions critical to execution
- **Example:** "Plan a roadshow" → Ask cities, dates, budget first
- **Broadcasts:** Message type: planning_form

**When to Configure Pre-Run Questions:**
- Request is complex and needs clarification
- Agent behavior changes significantly based on answers
- User input is required before agent can proceed
- Example: ListCreationAgent for complex lists

### Post-Creation Refinement (Future)
- **When:** After resource is created
- **Why:** Enhance items/content based on user preferences
- **Mechanism:** Agent sub-task or separate refinement agent
- **Speed:** 2-3 seconds
- **Questions:** Open-ended, content-aware
- **Example:** "Improve my reading list" → Ask genre preferences
- **Broadcasts:** Message type: list_created (with refinement suggestions)

**Note:** Post-creation refinement is not currently part of the chat flow. It would be a follow-up message or separate agent run.

---

## File Organization

### Services (alphabetically)

```
app/services/
├── ai_intent_router_service.rb
│   └─ Fallback intent detection (not used if CombinedIntentComplexity works)
│
├── chat_completion_service.rb
│   └─ Main orchestrator, 1629 lines
│
├── chat_mention_parser.rb
│   └─ Parse @mentions and #references
│
├── chat_resource_creator_service.rb
│   └─ Create list/user/team/org from chat
│
├── chat_routing_service.rb
│   └─ Detect navigation intents (legacy, may be deprecated)
│
├── combined_intent_complexity_service.rb  ← OPTIMIZATION
│   └─ Single call: intent + complexity + parameters
│
├── combined_intent_parameter_service.rb
│   └─ Combined intent + parameter extraction
│
│
├── list_refinement_processor_service.rb
│   └─ Process user answers to refinement questions
│
├── list_refinement_service.rb
│   └─ Generate refinement questions after list creation
│
├── parameter_extraction_service.rb
│   └─ Extract parameters from natural language
│
└── question_generation_service.rb
    └─ Generate pre-creation planning questions
```

### Models

```
app/models/
├── chat.rb
│   └─ Stores conversation, has_one :chat_context, focused_resource
│
├── chat_context.rb (AR Model)
│   └─ Persistent planning state (state machine, parameters, questions, answers)
│
├── chat_ui_context.rb (Plain Ruby Object)
│   └─ Per-request UI configuration (suggestions, system_prompt, ui_config)
│
├── message.rb
│   └─ Individual message in chat (role, content, metadata)
│
└── message_feedback.rb
    └─ User rating/feedback on messages
```

### Controllers

```
app/controllers/
├── chats_controller.rb
│   ├─ create_message → Handle incoming message
│   ├─ show → Display single chat
│   ├─ index → List user's chats
│   └─ destroy → Archive chat
│
└── chat/
    ├── commands_controller.rb → Execute /search, /help
    └── message_feedbacks_controller.rb → Save feedback
```

### Views

```
app/views/
├── chats/
│   ├── show.html.erb → Main chat page
│   ├── index.html.erb → Chat list
│   └── _unified_chat.html.erb → Chat component (Stimulus)
│
└── message_templates/
    ├── _list_created.html.erb
    ├── _navigation.html.erb
    ├── _search_results.html.erb
    ├── _team_summary.html.erb
    ├── _user_profile.html.erb
    └── ... (other templates)
```

### Jobs

```
app/jobs/
├── process_chat_message_job.rb
│   └─ Background processing for LLM messages
│
└── pre_creation_planning_job.rb
    └─ (May exist) Background question generation
```

---

## Debugging & Monitoring

### Monitor Agent Runs from Chat

```ruby
# In Rails console
chat = Chat.find("uuid")

# Get all agent runs from this chat
chat.ai_agent_runs

# Check last agent run
run = chat.ai_agent_runs.last
puts run.status              # pending, awaiting_input, in_progress, paused, completed, failed
puts run.agent.name
puts run.pre_run_answers     # User answers to questions
puts run.output              # Agent's final output
puts run.tool_calls.count    # How many tools did it call?
puts run.tokens_used         # Total tokens
puts run.duration_seconds    # How long did it take?
```

### Monitor Messages by Type

```ruby
# Find all messages of a specific type
chat.messages.where(type: "planning_form")
chat.messages.where(type: "list_created")

# Check message payload
message = chat.messages.last
puts message.type    # planning_form, list_created, progress_indicator, etc.
puts message.data    # JSONB payload specific to type
```

### Test Intent Detection

```ruby
result = CombinedIntentComplexityService.new(
  user_message: "plan my roadshow",
  chat: chat,
  user: user,
  organization: org
).call

puts result.success?
puts result.data[:intent]           # create_list, create_resource, etc.
puts result.data[:is_complex]       # true/false
puts result.data[:complexity_indicators]  # [multi_location, time_bound, ...]
```

---

---

## Services & Agents Reference

### Phase 1: Fast Intent Detection

| Component | Purpose | Model | Location |
|-----------|---------|-------|----------|
| **CombinedIntentComplexityService** | Detect intent + complexity + parameters in one call | gpt-4.1-nano | `app/services/combined_intent_complexity_service.rb` |

**Why One Call?** Combines three operations (intent, complexity, parameters) into a single LLM call, saving 1+ seconds per message.

### Phase 2: Agent-Based Execution

| Component | Purpose | Location |
|-----------|---------|----------|
| **ListCreationAgent** | Create lists (simple or complex with pre-run questions) | Seeded in `db/seeds.rb` |
| **ResourceCreationAgent** | Create users, teams, organizations | Seeded in `db/seeds.rb` |
| **SearchAgent** | Execute /search commands | Seeded in `db/seeds.rb` |
| **NavigationAgent** | Route to pages | Seeded in `db/seeds.rb` |
| **GeneralQAAgent** | Answer general questions with tools | Seeded in `db/seeds.rb` |

**Agent Execution:**
- `AgentExecutionService` - Orchestrates LLM + tool loop
- `AgentContextBuilder` - Composes system prompt
- `AgentToolExecutorService` - Executes tools (CRUD, search, HITL)
- `AgentTriggerService` - Trigger agents from chat
- `AgentRunJob` - Background execution

See [AGENTS.md](AGENTS.md) for complete agent reference.

### Phase 3: Helper Services (Called by Agents)

| Service | Purpose | Model | Location |
|---------|---------|-------|----------|
| **ItemGenerationService** | Generate domain-specific items | gpt-5.4-2026-03-05 | `app/services/item_generation_service.rb` |
| **ListCreationService** | Create list with hierarchical structure | Internal | `app/services/list_creation_service.rb` |

See [ITEM_GENERATION.md](ITEM_GENERATION.md) for details.

### Deprecated Services (Being Removed)

These are superseded by the agent-based architecture:

| Service | Why Deprecated | Replacement |
|---------|---|---|
| **ChatCompletionService** | Agents orchestrate directly | Agent framework |
| **ChatContextHandler** | Agent runs track state | AiAgentRun model |
| **QuestionGenerationService** | Handled by agent.pre_run_questions | Agent config |
| **ListRefinementService** | Not part of chat flow | Future refinement agent |
| **PreCreationPlanningJob** | Questions now in agent config | Agent pre-run phase |

### Message Types

See [MESSAGE_TYPES.md](MESSAGE_TYPES.md) for complete reference on all message types that can be displayed in chat.

---

## Testing Checklist

### Intent Detection
- [ ] CombinedIntentComplexityService returns correct intent in <2 seconds
- [ ] is_complex flag accurate for simple vs complex requests
- [ ] complexity_indicators populated for complex requests
- [ ] planning_domain detected correctly (event, project, travel, etc.)

### Agent Routing & Execution
- [ ] ListCreationAgent triggered for create_list intent
- [ ] ResourceCreationAgent triggered for create_resource intent
- [ ] SearchAgent triggered for search/command intent
- [ ] NavigationAgent triggered for navigate_to_page intent
- [ ] GeneralQAAgent triggered for general_question intent

### Simple List Creation
- [ ] Simple list request completes in <3 seconds
- [ ] No pre-run questions shown (skipped for simple)
- [ ] List created with default category
- [ ] Message type: list_created

### Complex List Creation
- [ ] Complex list shows planning form in <1 second
- [ ] Pre-run questions displayed correctly
- [ ] User answers stored in agent.pre_run_answers
- [ ] Agent executes after answers submitted
- [ ] Items generated for each sublist (location/phase/etc)
- [ ] Items are location-specific, not generic duplicates
- [ ] List created after ~15-20s total
- [ ] Message type: list_created with summary

### Agent Human-in-the-Loop (HITL)
- [ ] Agent can ask_user() and pause
- [ ] User response stored in AiAgentInteraction
- [ ] Agent resumes with user's answer
- [ ] HITL interactions show message type: agent_paused

### Message Types
- [ ] Message type field populated correctly (text, planning_form, list_created, etc.)
- [ ] Message data payload includes all required fields
- [ ] Frontend renders each message type correctly
- [ ] Turbo Streams updates progress in real-time

### Commands & Navigation
- [ ] /search command executes synchronously
- [ ] Navigation intent routes correctly
- [ ] Both broadcast within <1 second

### Security
- [ ] Prompt injection detection still works
- [ ] Content moderation check passes/fails appropriately
- [ ] Organization scoping enforced (no cross-org data)

### Persistence
- [ ] Chat history preserved across sessions
- [ ] Agent runs queryable by chat_id
- [ ] Message types stored correctly in database
