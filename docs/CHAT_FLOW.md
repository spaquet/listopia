# Chat System Flow & Architecture

Complete guide to how user messages flow through Listopia's unified chat system, from input to response.

**Important:** This flow is **domain-agnostic** and works for ANY type of list. The system doesn't hardcode specific domains - it intelligently adapts to whatever the user is planning (events, courses, recipes, projects, reading lists, etc.).

## Quick Summary

**Single Unified Chat Interface** - Handles everything from general questions to list creation to resource management, for any domain.

**Key Flows:**
1. **Simple Requests** → Direct response or creation (0.5-1s)
   - Examples: Quick grocery list, simple task list
2. **Complex Requests** → Ask clarifying questions first (1-2s to show form) → Generate context-appropriate items for subdivisions (10-15s)
   - LLM intelligently detects best subdivision type (locations, books, modules, phases, topics, etc.)
   - ItemGenerationService generates items specific to each subdivision
   - Examples: Roadshow with locations, reading list with books, course with modules
3. **Commands** → Synchronous processing (0.5s)
4. **Navigation** → Route to page (0.3s)
5. **Resource Creation** → Collect missing parameters → Create

**Key Innovation (2026-03-21):** Subdivision detection and item generation are fully generic. The system uses LLM to determine the best way to organize ANY list, then generates appropriate items. See [ITEM_GENERATION.md](ITEM_GENERATION.md) for details.

---

## Complete Message Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ User Types Message in Chat                                   │
└────────────┬────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────┐
│ ChatsController#create_message                              │
├─────────────────────────────────────────────────────────────┤
│ 1. Prompt injection detection                               │
│ 2. Content moderation check                                 │
│ 3. Save message to database                                 │
│ 4. Parse @mentions and #references                          │
│ 5. Detect if command (/search, /help, etc)                 │
└────────────┬────────────────────────────────────────────────┘
             │
    ┌────────┴────────┐
    │                 │
    ▼ COMMAND         ▼ LLM MESSAGE
    │                 │
    │                 ▼
    │        ┌─────────────────────────────────────┐
    │        │ ProcessChatMessageJob (Async)       │
    │        │ Queued to background worker         │
    │        └────────────┬────────────────────────┘
    │                     │
    │        ┌────────────▼─────────────────────┐
    │        │ ChatCompletionService#call       │
    │        ├─────────────────────────────────┤
    │        │ 1. Check ChatContext state       │
    │        │ 2. Detect intent & complexity    │
    │        │    (CombinedIntentComplexity)   │
    │        │ 3. Route by intent               │
    │        │ 4. Process response              │
    │        └────────────┬────────────────────┘
    │                     │
    │        ┌────────────┴────────────────────────┐
    │        │                                     │
    │        ▼ COMPLEX                 ▼ SIMPLE
    │        │                         │
    │        ▼                         ▼
    │   ┌──────────────────┐      ┌────────────────────┐
    │   │ PRE-CREATION     │      │ CREATE/RESPONSE    │
    │   │ PLANNING         │      │ IMMEDIATELY        │
    │   │                  │      │                    │
    │   │ Show 3 questions │      │ Generate response  │
    │   │ Await user answers       │ or create list     │
    │   └────────────┬─────┘      └─────────┬──────────┘
    │                │                       │
    │        ┌───────▼────────┐             │
    │        │ User Answers   │             │
    │        │ Questions      │             │
    │        └───────┬────────┘             │
    │                │                       │
    │        ┌───────▼────────────────────┐ │
    │        │ Create Enriched List       │ │
    │        │ with Refinements           │ │
    │        └───────┬────────────────────┘ │
    │                │                       │
    └────────────────┼───────────────────────┘
                     │
                     ▼
    ┌─────────────────────────────────────┐
    │ Turbo Stream Broadcast Response      │
    │ Replace loading indicator with       │
    │ actual message/result                │
    └─────────────────────────────────────┘
                     │
                     ▼
    ┌─────────────────────────────────────┐
    │ Frontend Renders Message             │
    │ Detects type and displays:           │
    │ - Markdown text                      │
    │ - Templated results                  │
    │ - List created confirmation          │
    │ - Questions form (if complex)        │
    └─────────────────────────────────────┘
```

---

## Intent Types & Routing

### What is Intent?

Intent is the **user's goal** - what they're trying to accomplish. The system detects this automatically and routes the message appropriately.

### Intent Types

| Intent | What User Wants | Processing | Example |
|--------|-----------------|------------|---------|
| **create_list** | Create a plan/project/list | Check complexity → Show questions or create immediately | "Plan my roadshow" |
| **create_resource** | Add user/team/organization | Collect missing params → Create | "Add user john@example.com" |
| **navigate_to_page** | Go to a specific page | Route page navigation | "Show users list" |
| **manage_resource** | Update/delete existing | Execute operation | "Archive the budget list" |
| **search_data** | Find something | Execute search | "Find lists about budget" |
| **general_question** | Ask anything else | Call LLM with tools | "How do I use tags?" |

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
Step 1: Intent Detection
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

Step 2: Check Complexity
  → NOT COMPLEX, skip pre-creation planning
  → Need category clarification

Step 3: Ask Category
  System: "Should this be a personal or professional list?"
  User: "Personal"

Step 4: Create List
  Service: ChatResourceCreatorService
  Creates: List with title="grocery list", category="personal"
  Items: Extracted from context or wait for user to add

Step 5: Response
  "I've created your grocery list. You can start adding items!"

Total Time: ~3 seconds ✅
```

---

### Scenario 2: Complex List with Pre-Creation Planning

**User Input:** "Help me plan a roadshow across the US"

```
Step 1: Intent Detection
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

Step 2: Trigger Pre-Creation Planning
  Service: ChatCompletionService#handle_pre_creation_planning
  → Set state: pending_pre_creation_planning

Step 3: Generate Questions
  Service: QuestionGenerationService
  Model: gpt-4.1-nano (fast question generation)
  Time: ~1-2 seconds
  Questions Generated: 3 clarifying questions specific to the domain
    Q1: "What is the target schedule for the roadshow, including start and end dates?"
    Q2: "What is the estimated budget allocated for the entire roadshow?"
    Q3: "How many locations or cities are planned for the roadshow, and what resources are available for each?"

Step 4: Show Form
  Chat displays pre-creation planning form with questions
  Background Job: PreCreationPlanningJob
  User sees form immediately (~100ms after clicking submit, actual questions pushed via Turbo Stream)

Step 5: User Provides Answers
  "June and September of this year. $500,000.
   New York, Los Angeles, Chicago, San Francisco, Seattle"

Step 6: Process Answers
  Service: ChatContextHandler#process_answers or ChatCompletionService
  Model: gpt-5-nano
  Extracts from user answers:
    - locations: ["New York", "Los Angeles", "Chicago", "San Francisco", "Seattle"]
    - budget: "$500,000"
    - timeline: "June 2026 to September 2026"
    - planning_domain: "event"
  Stores in: chat_context.pre_creation_answers and chat_context.parameters

Step 7: Detect Subdivision Type
  Service: ParameterMapperService or LLM-based detection
  Determines subdivision type based on extracted params:
    → Has locations array → Use :locations subdivision
  Stores in: chat_context.hierarchical_items[:subdivision_type]
  For each subdivision, calls ItemGenerationService:

Step 8: Generate Location-Specific Items
  Service: ItemGenerationService (NEW - refactored 2026-03-21)
  Model: gpt-5.4-2026-03-05 (reasoning model for quality)
  For each location (5 calls total, could be parallelized):
    Input:
      - List title: "roadshow for Listopia"
      - Description: "Budget: $500,000 | Start: June 2026"
      - Category: "professional"
      - Planning context: locations, budget, timeline, etc.
      - Sublist title: "New York" (or other location)

    Output: 5-8 location-specific items
      - Confirm venue booking at Times Square location
      - Arrange local transportation logistics
      - Coordinate with NY-based vendors and partners
      - Plan media outreach for NY market
      - Setup local team accommodations
      - Arrange audio/visual equipment for NYC venue

Step 9: Create List with Items
  Service: ChatResourceCreatorService → ListCreationService#create_list_with_structure
  Creates:
    Main List: "roadshow for Listopia"
    ├─ Sub-list: "New York" (with 5-8 generated items)
    ├─ Sub-list: "Los Angeles" (with 5-8 generated items)
    ├─ Sub-list: "Chicago" (with 5-8 generated items)
    ├─ Sub-list: "San Francisco" (with 5-8 generated items)
    └─ Sub-list: "Seattle" (with 5-8 generated items)

  Note: Main list items are cleared (empty) as all work is now specific to each location

Step 10: Response with Summary
  Broadcast via Turbo Stream
  Message: "Perfect! I've created a roadshow plan across 5 cities:
   - Locations: New York, Los Angeles, Chicago, San Francisco, Seattle
   - Timeline: June - September 2026
   - Budget: $500,000
   - Each location has specific tasks for venue booking, logistics, partnerships, media, and team coordination"

Total Time:
  - Question display: ~100ms perceived (questions generated in background)
  - Item generation: ~10-15 seconds (5 cities × 2-3s per city)
  - List creation: ~2-3 seconds
  - Total user perceived: User submits answers → 15-20s → List appears ✅
```

---

### Scenario 3: Navigation Intent

**User Input:** "Show me the users list"

```
Step 1: Intent Detection
  Service: CombinedIntentComplexityService
  Result: {
    intent: "navigate_to_page",     ← KEY: Navigation
    path: "admin_users"
  }

Step 2: Navigation Response
  Service: ChatCompletionService#handle_navigation_intent
  Creates message with type "navigation"

Step 3: Frontend Navigation
  JavaScript detects message type
  Triggers: window.location or Turbo.visit("/admin/users")

Step 4: Page Loads
  User sees users page in new tab or replaces current view

Total Time: ~0.5 seconds ✅
```

---

### Scenario 4: Command Processing

**User Input:** "/search budget"

```
Step 1: Controller Detects Command
  File: ChatsController#create_message (Line 120)
  Message starts with "/" → Command processing

Step 2: Execute Command
  Service: ChatCompletionService#execute_command
  Time: ~0.5 seconds

Step 3: Synchronous Response
  Results: Found 3 lists matching "budget"
  Response shown immediately in chat

Total Time: ~0.5 seconds ✅ (No background job)
```

---

### Scenario 5: Resource Creation (User)

**User Input:** "Create a user for john@example.com"

```
Step 1: Intent Detection
  Result: {
    intent: "create_resource",
    resource_type: "user",
    parameters: {
      email: "john@example.com"
    },
    missing: ["name"]
  }
  → Set state: pending_resource_creation

Step 2: Ask Missing Parameter
  System: "What's the user's full name?"
  User: "John Smith"

Step 3: Collect All Parameters
  Email: john@example.com
  Name: John Smith
  Role: Not specified → Use default "member"

Step 4: Create User
  Service: ChatResourceCreatorService
  Creates: User with email, sends magic link invitation

Step 5: Response
  "Created user john@example.com. Invitation sent."

Total Time: ~3-4 seconds (including user input) ✅
```

---

### Scenario 6: General Question (No Intent Match)

**User Input:** "How do I add people to my team?"

```
Step 1: Intent Detection
  Result: {
    intent: "general_question"
  }

Step 2: LLM Response with Tools
  Service: ChatCompletionService#call_llm_with_tools
  Model: gpt-5-mini (default, configured in chat.metadata)
  Tools Available:
    - navigate_to_page (routing)
    - list_lists, list_users, list_teams (read)
    - create_list, create_user (create)
    - And 10+ other tools

Step 3: LLM Generates Response
  LLM reads system prompt + message history
  Formulates helpful answer with examples
  May call tools if helpful (e.g., list_teams to show examples)

Step 4: Tool Execution (if called)
  Service: LLMToolExecutorService
  Execute tool, return results to LLM

Step 5: Final Response
  LLM synthesizes answer + tool results
  "You can add people to your team by:
   1. Click the team
   2. Click 'Invite member'
   3. Enter email address
   4. They'll receive an invitation..."

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

## List Refinement vs Pre-Creation Planning

These are **different systems** for different situations:

### Pre-Creation Planning
- **When:** Before list is created
- **Why:** To gather context first
- **Service:** QuestionGenerationService
- **Model:** gpt-4.1-nano
- **Speed:** 1-2 seconds
- **Questions:** 3 domain-specific questions
- **Example:** "Plan a roadshow" → Ask cities, dates, budget first

### List Refinement
- **When:** After list is created
- **Why:** To refine items based on answers
- **Service:** ListRefinementService
- **Model:** gpt-5 (reliable, not nano)
- **Speed:** 2-3 seconds
- **Questions:** Open-ended, category-aware
- **Example:** "Improve my existing grocery list" → Ask dietary preferences

### Which Should Be Used?

Use **Pre-Creation Planning** for:
- Complex requests (multi-location, time-bound, hierarchical)
- Professional planning (projects, events, roadshows)
- Requests that need context before item creation

Use **List Refinement** for:
- Simple requests that need enhancement
- Existing lists needing improvements
- Learning/personal growth lists

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

### Check Chat Context State

```ruby
# In Rails console
chat = Chat.find("uuid")
context = chat.chat_context
puts context.state  # initial, pre_creation, resource_creation, completed
puts context.status  # pending, analyzing, awaiting_user_input, processing, complete, error
puts context.post_creation_mode  # true if showing "keep/clear" buttons
puts context.inspect
```

### Monitor Performance

```ruby
# Check last message processing time
message = chat.messages.last
puts message.metadata["processing_time_ms"]

# Check model used
puts chat.metadata["model"]
```

### Test Intent Detection

```ruby
result = CombinedIntentComplexityService.new(
  user_message: message,
  chat: chat,
  user: user,
  organization: org
).call

puts result.data.inspect
```

---

---

## Services Reference

### Core Chat Processing

| Service | Purpose | Models | Location |
|---------|---------|--------|----------|
| **ChatCompletionService** | Main orchestrator for message processing | gpt-4.1-nano, gpt-5 | `app/services/chat_completion_service.rb` |
| **CombinedIntentComplexityService** | Detect intent and complexity in one call | gpt-4.1-nano | `app/services/combined_intent_complexity_service.rb` |
| **QuestionGenerationService** | Generate pre-creation clarifying questions | gpt-4.1-nano | `app/services/question_generation_service.rb` |
| **ListRefinementService** | Generate post-creation refinement questions | gpt-5 | `app/services/list_refinement_service.rb` |
| **ItemGenerationService** | Generate items for sublists (NEW 2026-03-21) | gpt-5.4-2026-03-05 | `app/services/item_generation_service.rb` |

### List Creation

| Service | Purpose | Location |
|---------|---------|----------|
| **ChatResourceCreatorService** | Create lists/users/teams from chat parameters | `app/services/chat_resource_creator_service.rb` |
| **ListCreationService** | Create list with items and nested structure | `app/services/list_creation_service.rb` |

### Supporting Services

| Service | Purpose | Location |
|---------|---------|----------|
| **PreCreationPlanningJob** | Background job for question generation | `app/jobs/pre_creation_planning_job.rb` |
| **ProcessChatMessageJob** | Background job for message processing | `app/jobs/process_chat_message_job.rb` |

### Key Methods in ChatCompletionService

| Method | Purpose |
|--------|---------|
| `call` | Main entry point, routes by intent |
| `handle_list_creation_intent` | Routes simple vs complex list flows |
| `handle_pre_creation_planning_response` | Process user answers and create enriched list |
| `handle_context_reuse_choice` | Handle user choice: keep or clear planning context |
| `process_message` | Unified message processor for both sync and async |

### State Management Services

| Service | Purpose | Location |
|---------|---------|----------|
| **ChatContextHandler** | Orchestrates ChatContext state transitions and service calls | `app/services/chat_context_handler.rb` |
| **ParameterExtractionService** | Extract parameters from user messages for resource creation | `app/services/parameter_extraction_service.rb` |

For more details on ItemGenerationService, see: [ITEM_GENERATION.md](ITEM_GENERATION.md)

---

## Testing Checklist

- [ ] Simple list request completes in <2 seconds
- [ ] Complex list shows questions form in <3 seconds (questions generated async)
- [ ] Pre-creation planning questions are domain-appropriate
- [ ] Items are generated for each sublist (location/phase/etc)
- [ ] Items are location-specific or phase-specific, not generic duplicates
- [ ] List created after answering questions (~15-20s total for 5 sublists)
- [ ] Navigation intent routes correctly
- [ ] Commands execute synchronously
- [ ] Resource creation collects missing params
- [ ] Markdown and templates render correctly
- [ ] Security checks pass/fail appropriately
- [ ] Chat history preserved across sessions
