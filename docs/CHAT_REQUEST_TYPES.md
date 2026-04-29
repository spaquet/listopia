# Chat Request Types: Simple, Complex, Nested Lists, and More

Listopia's unified chat system automatically detects request complexity and routes to the appropriate **AI Agent**.

**Important:** All request types are **domain-agnostic**. The system handles ANY type of planning request (events, courses, recipes, projects, learning journeys, etc.) using the same intelligent detection and generation logic. Test examples may emphasize events/travel, but the architecture is fully generic.

**Agent-Centric Architecture:**
- Intent detection is **fast** (CombinedIntentComplexityService, <2s)
- Execution is **agent-based** (specialized agents for each intent type)
- State is **agent runs** (no separate ChatContext model)
- Audit trail is **automatic** (every agent run is recorded)

---

## Quick Reference

| Request Type | Intent | Agent | Time to Response | Example |
|--------------|--------|-------|------------------|---------|
| **Simple List** | create_list | ListCreationAgent | 1-2s | "Buy groceries" |
| **Complex List** | create_list | ListCreationAgent + HITL | 2-3s to show form | "Plan US roadshow" |
| **Nested List** | create_list | ListCreationAgent + ItemGen | 15-20s | "Roadshow with cities" |
| **Command** | search_data | SearchAgent | <1s | "/search budget" |
| **Navigation** | navigate_to_page | NavigationAgent | <1s | "Show users list" |
| **Resource Create** | create_resource | ResourceCreationAgent | 2-3s + user input | "Create user john@..." |
| **General Question** | general_question | GeneralQAAgent | 2-3s | "How do I...?" |

---

## 1. Simple List Requests

### What Makes a List "Simple"?

A request is **SIMPLE** when the user provides enough context to create the list immediately:

✓ **Simple Examples:**
- "Buy groceries"
- "Gym workout routine"
- "Mac setup tasks"
- "Reading list for better manager"
- "Trip packing checklist"

❌ **Why these are simple:**
- User knows what items are needed
- No ambiguity about scope
- No missing critical information
- System context provides sufficient detail

### Flow

```
User: "Create a workout list"
  ↓
CombinedIntentComplexityService
  intent: "create_list"
  is_complex: false ← KEY
  ↓
Check category: Need clarification? → "Professional or personal?"
User: "Personal"
  ↓
Create List Immediately
  title: "Workout List"
  category: "personal"
  items: []  (User adds items manually)
  ↓
Response: "Created workout list. You can add exercises now!"
Total Time: ~1-2 seconds
```

### Agent Flow

```
1. CombinedIntentComplexityService (2s)
   └─ Detects: intent=create_list, is_complex=false

2. Route to ListCreationAgent
   └─ No pre_run_questions configured

3. Agent Executes
   ├─ Checks: is_complex?
   ├─ Result: NO
   └─ Skips pre-run questions

4. Create List Immediately
   ├─ Calls tool: create_list
   └─ Returns output

5. Broadcast Response
   └─ Message type: list_created
```

### When Pre-Run Questions Are Skipped

```ruby
# In ListCreationAgent execution
if complexity == false
  # SKIP pre-run questions
  # Create list immediately
  create_list(parameters)
end
```

---

## 2. Complex List Requests

### What Makes a List "Complex"?

A request is **COMPLEX** when critical information is missing that would affect the list structure:

✓ **Complex Examples:**
- "Plan a roadshow across the US" → Missing: cities, dates, budget
- "Organize our summer retreat" → Missing: dates, location, team size
- "8-week Python course" → Missing: level, format, time commitment
- "Vacation to Europe" → Missing: dates, budget, companions
- "Sprint planning" → Missing: team, deliverables, timeline

✓ **Complexity Indicators:**
- `multi_location` - Multiple places involved
- `time_bound` - Timeline/deadline constraints
- `hierarchical` - Has phases or structure
- `large_scope` - Big project or ambitious goal
- `coordination` - Involves multiple people
- `ambiguous` - Unclear scope or requirements

### Flow

```
User: "Plan a US roadshow in June"
  ↓
CombinedIntentComplexityService (2s)
  intent: "create_list"
  is_complex: true ← KEY
  complexity_indicators: ["multi_location", "time_bound"]
  planning_domain: "event"
  ↓
Trigger Pre-Creation Planning
  Set state: pending_pre_creation_planning
  ↓
QuestionGenerationService (1-2s)
  Model: gpt-4.1-nano
  Domain: event
  Category: professional
  ↓
Questions Displayed:
  Q1: "Which cities will you visit?"
  Q2: "What's your timeline (dates/duration)?"
  Q3: "What activities at each stop?"
  ↓
User Answers:
  "NYC, Chicago, Boston, Denver (June 1-30, 2 days each)
   Product presentation, customer meetings, team training"
  ↓
Enrich List Structure
  Create main list: "US Roadshow June"
  Create sub-lists:
    - NYC (2 days)
    - Chicago (2 days)
    - Boston (2 days)
    - Denver (2 days)
  Add items to each:
    - Venue setup
    - Marketing push
    - Logistics
    - Follow-ups
  ↓
Response: "Created structured roadshow plan with 4 cities!"
Total Time: 2-3 seconds perceived (+ user answer time)
```

### Agent Flow

```
1. CombinedIntentComplexityService (2s)
   └─ Detects: intent=create_list, is_complex=true

2. Route to ListCreationAgent
   ├─ Config has pre_run_questions
   └─ Status: pending → awaiting_input

3. Show Pre-Run Questions (HITL)
   ├─ Message type: planning_form
   └─ Broadcast via Turbo Stream

4. User Submits Answers
   ├─ Answers stored in AiAgentRun#pre_run_answers
   └─ AgentRunJob enqueued

5. Agent Executes (Background)
   ├─ Extract parameters
   ├─ Detect subdivision type (locations, phases, etc.)
   ├─ Call ItemGenerationService for each subdivision
   ├─ Create list structure
   └─ Message type: progress_indicator (real-time updates)

6. Completion & Response
   ├─ Message type: list_created
   └─ Status: completed
```

### Complexity Detection

**Handled by:** `CombinedIntentComplexityService`

Complexity is detected through a single LLM call (gpt-4.1-nano) that evaluates:

```ruby
# Result from CombinedIntentComplexityService
{
  intent: "create_list",
  is_complex: true,
  complexity_indicators: [
    :multi_location,      # Has locations/places
    :time_bound,          # Has dates/timeline
    :hierarchical,        # Has phases/structure
    :large_scope,         # Ambitious or multi-part
    :coordination         # Involves multiple people
  ],
  planning_domain: "event",     # event, project, travel, learning, personal
  confidence: 0.92              # Confidence level
}
```

**Decision:** If `is_complex >= 2 indicators` → Show pre-run questions

### Complexity Confidence Levels

```
HIGH confidence (>90%):
  - 3+ complexity indicators present
  - Clear pattern match
  - Example: "Roadshow across 5 US cities" → multi_location + time_bound + coordination

MEDIUM confidence (70-90%):
  - 2 complexity indicators
  - Some ambiguity
  - Example: "Plan summer event" → Could be simple or complex

LOW confidence (<70%):
  - 1 indicator or unclear
  - Ask user for clarification
  - Example: "Organize something" → Too vague
```

---

## 3. Nested List Requests (Hierarchical)

### What is a Nested/Hierarchical List?

A list with **sub-lists** organized by:
- **Location:** Cities, regions, venues
- **Phase:** Before, during, after
- **Team:** Different team members' tasks
- **Category:** Grouped by type or domain

### Examples of Nested Requests

✓ **Location-based:**
```
"Plan a roadshow across NYC, Chicago, Boston, Denver"
→ Main list: "Roadshow"
→ Sub-lists: "NYC", "Chicago", "Boston", "Denver"
→ Each city has venue, marketing, logistics tasks
```

✓ **Phase-based:**
```
"Plan a product launch: pre-launch, launch day, post-launch"
→ Main list: "Product Launch"
→ Sub-lists: "Pre-launch", "Launch Day", "Post-launch"
→ Each phase has specific tasks
```

✓ **Team-based:**
```
"Assign sprint tasks across frontend, backend, design teams"
→ Main list: "Sprint Tasks"
→ Sub-lists: "Frontend", "Backend", "Design"
→ Each team has their specific tasks
```

### Detection & Creation

**Nested structures are detected during parameter extraction:**

```ruby
# In CombinedIntentComplexityService or ParameterExtractionService
has_nested_structure = detect_nested_patterns(message)

if has_nested_structure
  nested_lists: [
    { title: "New York", items: [...] },
    { title: "Chicago", items: [...] },
    { title: "Boston", items: [...] }
  ]
end
```

### Creation Flow

```
User: "Organize US roadshow across NYC, Chicago, Boston"
  ↓
Detect: hierarchical pattern → has_nested_structure: true
  ↓
Extract Parameters:
  Main title: "US Roadshow"
  Cities: ["NYC", "Chicago", "Boston"]
  ↓
ListHierarchyService
  Create main list: "US Roadshow"
  Create sub-list: "NYC"
    Add items: venue, marketing, transportation, follow-up
  Create sub-list: "Chicago"
    Add items: venue, marketing, transportation, follow-up
  Create sub-list: "Boston"
    Add items: venue, marketing, transportation, follow-up
  ↓
Result Structure:
  List: "US Roadshow"
  ├─ Items: [Pre-roadshow planning items]
  ├─ Sub-list: "NYC"
  │   └─ Items: [venue, marketing, ...]
  ├─ Sub-list: "Chicago"
  │   └─ Items: [venue, marketing, ...]
  └─ Sub-list: "Boston"
      └─ Items: [venue, marketing, ...]
```

### Agent Flow for Nested Lists

**Handled by:** ListCreationAgent

The agent automatically detects nested patterns and:

1. **Detects subdivision type** from user parameters
   - `:locations` - geographic divisions (cities, regions)
   - `:phases` - project phases (pre, during, post)
   - `:books` - books in a reading list
   - `:modules`, `:chapters`, `:weeks` - course/learning divisions
   - `:teams` - team-specific work
   - Custom subdivisions

2. **Calls ItemGenerationService** for each subdivision
   - Generates 5-8 location-specific items
   - NOT generic duplicates
   - Considers context and constraints

3. **Creates hierarchical structure**
   ```
   List: "US Roadshow"
   ├─ Sublist: "NYC" [6 items]
   ├─ Sublist: "Chicago" [5 items]
   └─ Sublist: "Seattle" [4 items]
   ```

### Nested List Best Practices

1. **2-3 levels max:** Parent → Children only
2. **Consistent naming:** "City Name", "Phase Name"
3. **Shared context:** Main list for cross-cutting concerns
4. **Item distribution:** Common items in main list, specific in sub-lists

---

## 4. Command Requests

### What is a Command?

Message starting with **`/`** — processed synchronously, not via LLM

### Command Examples

```
/search <query>      → Search lists, items, tags
/help               → Show available commands
/clear              → Clear conversation history
/browse [status]    → Browse lists by status (draft, active, completed)
/tag <tagname>      → Search by tag
```

### Flow

```
User: "/search budget"
  ↓
ChatsController detects "/" at start
  ↓
execute_command("search", "budget")  [SYNCHRONOUS]
  ↓
Search Service
  Find lists matching "budget"
  ↓
Immediate Response
  "Found 3 lists: Budget 2024, Travel Budget, Project Budget"
Total Time: <1 second ✅
```

### Agent Flow

```
1. ChatsController#create_message
   └─ Detects: message starts with "/"

2. Route to SearchAgent (or CommandAgent variant)
   ├─ Synchronous execution (no background job)
   ├─ Parse command: /search budget
   └─ Query: "budget"

3. Agent Executes (Immediate)
   ├─ Call tool: search(query)
   ├─ Find matching lists/items
   └─ Format results

4. Broadcast Response
   ├─ Message type: search_results or command_response
   └─ Turbo Stream update
```

### Synchronous vs Asynchronous

```ruby
# In ChatsController#create_message
if message.content.start_with?("/")
  # SYNCHRONOUS: SearchAgent executes immediately
  result = SearchAgent.trigger_manual(input: message, ...)
  # Response returned to user within 1 second
else
  # ASYNCHRONOUS: ProcessChatMessageJob queued
  # Runs in background, updates via Turbo Stream
  ProcessChatMessageJob.perform_later(chat, message)
end
```

---

## 5. Navigation Intent Requests

### What is Navigation?

User asks to go to a specific page → System navigates instead of responding

### Navigation Examples

```
"Show users list"          → Navigate to /admin/users
"Go to teams"              → Navigate to /admin/teams
"Show my lists"            → Navigate to /lists
"View organization"        → Navigate to /organizations/:id
"Browse archive"           → Navigate to /lists?status=archived
```

### Agent Flow

```
User: "Show me the users list"
  ↓
CombinedIntentComplexityService (2s)
  ├─ Intent: "navigate_to_page"
  └─ Path: "/admin/users"
  ↓
Route to NavigationAgent
  ├─ Synchronous execution
  └─ Status: in_progress → completed
  ↓
Agent Executes
  ├─ Call tool: navigate_to_page(path: "/admin/users")
  └─ Output: { path: "/admin/users" }
  ↓
Broadcast Navigation Message
  ├─ Message type: "navigation"
  └─ Data: { path: "/admin/users", target: "_self" }
  ↓
Frontend Detects Type
  ├─ JavaScript listener triggers
  └─ Turbo.visit("/admin/users")
  ↓
Page Navigates
Total Time: <1 second ✅
```

### Frontend Handling

```javascript
// app/javascript/controllers/chat_navigation_controller.js
document.addEventListener('turbo:load', () => {
  const navMsg = document.querySelector('[data-message-type="navigation"]');
  if (navMsg) {
    const path = navMsg.dataset.navigationPath;
    Turbo.visit(path);
  }
});
```

---

## 6. Resource Creation Requests

### Types of Resources

1. **Users:** "Create a user for john@example.com"
2. **Teams:** "Add a new team called engineering"
3. **Organizations:** "Create organization acme-corp"
4. **Lists:** "Create a list called marketing tasks" (also handled as list creation)

### Example: Create User

```
User: "Create user john@example.com"
  ↓
CombinedIntentComplexityService
  intent: "create_resource"
  resource_type: "user"
  parameters: {
    email: "john@example.com"
  }
  missing: ["name", "role"]  ← KEY: collect these
  ↓
Check missing parameters
  → Ask for "name"
  ↓
User: "John Smith"
  ↓
Ask for "role" (optional)
  → User skips or says "member"
  ↓
ChatResourceCreatorService
  Create user: John Smith, john@example.com, member
  Send magic link invitation
  ↓
Response:
  "Created user john@example.com. Invitation sent."
```

### Agent Flow

```
User: "Create user john@example.com"
  ↓
CombinedIntentComplexityService (2s)
  ├─ Intent: "create_resource"
  ├─ Resource type: "user"
  └─ Missing params: ["name"]
  ↓
Route to ResourceCreationAgent
  ├─ Has pre_run_questions
  └─ Status: pending → awaiting_input
  ↓
Show Pre-Run Questions (HITL)
  ├─ Message type: "planning_form"
  └─ Question: "What's the user's full name?"
  ↓
User Submits: "John Smith"
  ├─ Answers stored in AiAgentRun
  └─ AgentRunJob enqueued
  ↓
Agent Executes
  ├─ Collect all parameters
  ├─ Call tool: create_user(email, name, role)
  ├─ Send magic link invitation
  └─ Output: { user_id, email, name }
  ↓
Broadcast Result
  ├─ Message type: "resource_created"
  └─ "Created user John Smith. Invitation sent."
```

---

## 7. General Questions (LLM + Tools)

### What Are General Questions?

Requests that don't match other intents — use LLM with access to tools

### Examples

```
"How do I add people to a team?"
"What's the difference between lists and items?"
"Can I share a list with my team?"
"How do I export my data?"
"What formats do you support?"
```

### Agent Flow

```
User: "How do I add people to my team?"
  ↓
CombinedIntentComplexityService (2s)
  ├─ Intent: "general_question"
  └─ No specific match
  ↓
Route to GeneralQAAgent
  ├─ Model: gpt-5-mini
  ├─ No pre_run_questions
  └─ Status: pending → in_progress
  ↓
Agent Executes (Background)
  ├─ Load tools: list_teams, navigate, search, etc.
  ├─ Build system prompt + message history
  ├─ LLM decides: "Should I call list_teams to show examples?"
  ├─ If yes: call tool, get results
  ├─ LLM synthesizes answer + results
  └─ Status: completed
  ↓
Broadcast Response
  ├─ Message type: "text"
  └─ "You can add people to your team by:
      1. Open your team
      2. Click 'Invite member'
      3. Enter their email
      4. They'll receive an invitation..."
  ↓
Total Time: ~2-3 seconds ✅
```

### Available Tools for GeneralQAAgent

```
Navigation:
  - navigate_to_page

Reading:
  - list_users, list_teams, list_lists, list_organizations
  - search

Creating:
  - create_user, create_team, create_list, create_organization

Updating:
  - update_user, update_team
  - suspend_user, unsuspend_user
```

---

## Decision Tree: Intent → Agent Routing

```
╔════════════════════════════════════════════════════╗
║ User Message in Chat                               ║
╚════════════┬──────────────────────────────────────┘
             │
    ┌────────┴────────┐
    │                 │
    ▼ COMMAND         ▼ MESSAGE
Starts with "/" DetectIntent
    │           (CombinedIntentComplexityService)
    ▼                 │
SearchAgent      ┌────┴──────┬─────────┬──────────┬─────────┐
    │            │           │         │          │         │
    │         create_     navigate_ create_   search_   general_
    │         list        to_page  resource   data     question
    │            │           │         │          │         │
    │            ▼           ▼         ▼          ▼         ▼
    │        ListCreation  Navigation ResourceCreation Search  GeneralQA
    │        Agent         Agent      Agent           Agent    Agent
    │            │           │         │          │         │
    │       ┌────┴────┐      │         │          │         │
    │    Complex?     │      │         │          │         │
    │     │           │      │         │          │         │
    │   YES NO        │      │         │          │         │
    │    │  │         │      │         │          │         │
    │    ▼  ▼         ▼      ▼         ▼          ▼         ▼
    │  Show Ask    Create  Navigate Collect  Execute  Call
    │  Form Params List    Page     Params    Search   LLM
    │    │   │       │      │         │          │      with
    │    │   │       │      │         │          │      Tools
    └────┼───┼───────┼──────┼─────────┼──────────┼──────────┐
         │   │       │      │         │          │          │
         └───┴───────┴──────┴─────────┴──────────┴──────────┘
                         │
                         ▼
                 Broadcast Response
                 (message type: list_created,
                  navigation, resource_created,
                  search_results, text, etc.)
```

**Flow:**
1. Detect command `/` or LLM message
2. Route to intent-specific agent (or SearchAgent for commands)
3. Agent executes (may show HITL form)
4. Broadcast appropriate message type
5. Frontend renders based on type

---

## Summary: Time to Response

| Request Type | Time to Form/Response | Time to Complete |
|--------------|----------------------|------------------|
| Simple List | 1-2s | 1-2s |
| Complex List (form show) | 2-3s | 2-3s + user time |
| Nested List (structure) | 3-4s | 3-4s + user time |
| Command | <1s | <1s |
| Navigation | <1s | <1s |
| Resource Create (form) | 2-3s | 2-3s + user time |
| General Question | 2-3s | 2-3s |

---

## Testing Each Request Type

### Simple List Agent Test
```ruby
# Trigger ListCreationAgent for simple request
message = "Create a grocery list"

# Expected:
# 1. CombinedIntentComplexityService: is_complex=false
# 2. ListCreationAgent triggered
# 3. No pre-run questions shown
# 4. List created in <3 seconds
# 5. Message type: list_created
```

### Complex List Agent Test
```ruby
# Trigger ListCreationAgent with pre-run questions
message = "Plan a roadshow across US cities"

# Expected:
# 1. CombinedIntentComplexityService: is_complex=true
# 2. ListCreationAgent triggered with pre_run_questions
# 3. Message type: planning_form displayed in <1 second
# 4. User submits answers
# 5. Agent generates items (15-20s total)
# 6. Message type: list_created with summary
```

### Nested List Agent Test
```ruby
# Trigger ListCreationAgent with subdivisions
message = "Organize roadshow: NYC, Chicago, Boston"

# Expected:
# 1. Agent detects nested pattern
# 2. Creates main list + 3 sublists
# 3. Calls ItemGenerationService for each location
# 4. Message type: progress_indicator (real-time updates)
# 5. Message type: list_created (final summary)
```

### Command Agent Test
```ruby
# Trigger SearchAgent synchronously
message = "/search budget"

# Expected:
# 1. SearchAgent executes immediately (no async)
# 2. Results returned in <1 second
# 3. Message type: search_results or command_response
```

### Navigation Agent Test
```ruby
# Trigger NavigationAgent
message = "Show users"

# Expected:
# 1. CombinedIntentComplexityService: intent=navigate_to_page
# 2. NavigationAgent executes immediately
# 3. Message type: navigation
# 4. Frontend auto-navigates to /admin/users
```

### Resource Creation Agent Test
```ruby
# Trigger ResourceCreationAgent
message = "Create user alice@example.com"

# Expected:
# 1. Intent: create_resource
# 2. ResourceCreationAgent triggered
# 3. Message type: planning_form (ask for missing name)
# 4. User submits name
# 5. Agent creates user, sends invitation
# 6. Message type: resource_created
```

### General QA Agent Test
```ruby
# Trigger GeneralQAAgent with tools
message = "How do I add team members?"

# Expected:
# 1. Intent: general_question
# 2. GeneralQAAgent executes (background)
# 3. LLM may call tools (list_teams, navigate, etc.)
# 4. Tools results fed back to LLM
# 5. Message type: text (full markdown response)
# 6. Response in ~2-3 seconds
```

---

## Related Documentation

- [MESSAGE_TYPES.md](./MESSAGE_TYPES.md) - All message types (planning_form, list_created, navigation, etc.)
- [CHAT_FLOW.md](./CHAT_FLOW.md) - Complete agent-based message flow
- [AGENTS.md](./AGENTS.md) - AI Agent system reference
- [CHAT_MODEL_SELECTION.md](./CHAT_MODEL_SELECTION.md) - Why gpt-4.1-nano for intent detection
- [ITEM_GENERATION.md](./ITEM_GENERATION.md) - How items are generated for sublists
