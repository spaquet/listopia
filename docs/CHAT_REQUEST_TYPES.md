# Chat Request Types: Simple, Complex, Nested Lists, and More

Listopia's unified chat system automatically detects request complexity and routes to the appropriate flow.

---

## Quick Reference

| Request Type | Detection | Processing | Time to Response | Example |
|--------------|-----------|------------|------------------|---------|
| **Simple List** | Low complexity | Direct creation | 1-2s | "Buy groceries" |
| **Complex List** | High complexity | Ask clarifying Q's | 2-3s to show form | "Plan US roadshow" |
| **Nested List** | Hierarchical pattern | Create sub-lists | 3-4s | "Roadshow with cities" |
| **Command** | Starts with `/` | Sync execution | <1s | "/search budget" |
| **Navigation** | Page route pattern | Route to page | <1s | "Show users list" |
| **Resource Create** | User/Team/Org pattern | Collect params | 2-3s | "Create user john@..." |
| **General Question** | No intent match | LLM + tools | 2-3s | "How do I...?" |

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

### Service Chain

```
CombinedIntentComplexityService (2s)
  ↓
Check: is_complex? = false
  ↓
Skip QuestionGenerationService
  ↓
ChatResourceCreatorService (0.2s)
  ↓
Response
```

### When Pre-Creation Planning is Skipped

```ruby
# In ChatCompletionService
combined_data = CombinedIntentComplexityService.call

if combined_data[:is_complex] == false
  # SKIP pre-creation planning
  # Go straight to list creation
  handle_list_creation(combined_data)
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

### Service Chain

```
CombinedIntentComplexityService (2s)
  ↓
Check: is_complex? = true
  ↓
QuestionGenerationService (1-2s)
  ↓
Show Form → User Answers
  ↓
ListHierarchyService (0.2s)
  ↓
Create List + Sub-lists
  ↓
Response
```

### Detection Logic

**File:** `app/services/list_complexity_detector_service.rb`

```ruby
def detect_complexity(message)
  indicators = []

  # Multi-location check
  indicators << :multi_location if multi_location?(message)

  # Time-bound check
  indicators << :time_bound if time_bound?(message)

  # Hierarchical check
  indicators << :hierarchical if hierarchical?(message)

  # Large scope check
  indicators << :large_scope if large_scope?(message)

  # Coordination check
  indicators << :coordination if coordination?(message)

  # Complex if 2+ indicators
  is_complex = indicators.count >= 2

  {
    is_complex: is_complex,
    indicators: indicators,
    confidence: confidence_level(indicators)
  }
end
```

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

### Service: ListHierarchyService

**File:** `app/services/list_hierarchy_service.rb`

**Purpose:** Create parent list with multiple sub-lists

```ruby
result = ListHierarchyService.new(
  parent_list: list,
  nested_structures: [
    { title: "NYC", items: [...] },
    { title: "Chicago", items: [...] }
  ],
  created_by_user: user,
  created_in_organization: org
).call

# Returns:
{
  parent_list: <List>,
  sublists: [<List>, <List>, ...],
  sublists_count: 3,
  errors: []
}
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

### Service Chain

```
ChatsController#create_message
  ↓
Detect: message.start_with?("/")
  ↓
ChatCompletionService#execute_command
  ↓
Case command_name
  when "search" → SearchService
  when "help" → help_response
  when "browse" → list_browsing
  ↓
Immediate response (no background job)
```

### Command Processing Code

```ruby
# In ChatsController#create_message
if message.content.start_with?("/")
  # SYNCHRONOUS processing
  command_result = ChatCompletionService.new(...).execute_command(...)
  # Return immediately
  respond_with_turbo_stream(command_result)
else
  # ASYNC processing via background job
  ProcessChatMessageJob.perform_later(...)
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

### Detection

```ruby
# In ChatRoutingService
def detect_navigation_intent(message)
  case message.downcase
  when /show.*users|list.*users|users.*page/i
    { action: :navigate, path: :admin_users }
  when /show.*teams|go.*teams|teams.*page/i
    { action: :navigate, path: :admin_teams }
  when /show.*lists|my.*lists|all.*lists/i
    { action: :navigate, path: :lists }
  # ... more routes
  end
end
```

### Flow

```
User: "Show me the users list"
  ↓
CombinedIntentComplexityService
  intent: "navigate_to_page" ← KEY
  path: "admin_users"
  ↓
handle_navigation_intent
  Create message type: "navigation"
  ↓
Turbo Stream broadcasts navigation message
  ↓
Frontend (JavaScript) detects type
  ├─ Turbo.visit("/admin/users")  OR
  └─ window.location.href = "/admin/users"
  ↓
Page navigates
Total Time: <1 second ✅
```

### Frontend Handling

```javascript
// app/javascript/controllers/chat_navigation_controller.js
document.addEventListener('turbo:load', () => {
  const navMessages = document.querySelectorAll('[data-navigation]');
  navMessages.forEach(msg => {
    const path = msg.dataset.navigationPath;
    Turbo.visit(path);
  });
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

### Parameter Collection

```ruby
# In ChatCompletionService#check_parameters_for_intent_optimized
missing_params = combined_data[:missing] || []

if missing_params.any?
  # Ask for each missing parameter
  # Store in pending_resource_creation state
  # Wait for user response
  state[:pending_resource_creation] = {
    resource_type: resource_type,
    extracted_params: extracted_params,
    missing_params: missing_params
  }
end
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

### Flow

```
User: "How do I add people to my team?"
  ↓
CombinedIntentComplexityService
  intent: "general_question" ← No specific match
  ↓
ChatCompletionService#call_llm_with_tools
  Model: gpt-5-mini (default)
  Available tools: list_teams, navigate, etc.
  ↓
LLM thinks: "User is asking how to add people"
  → Might suggest: navigate to team page
  → Or: explain the process
  → Or: list teams to show examples
  ↓
If LLM calls tool:
  LLMToolExecutorService
  Execute tool, return results
  ↓
LLM synthesizes response
  ↓
Response with context:
  "You can add people to your team by:
   1. Open your team
   2. Click 'Invite member'
   3. Enter their email
   4. They'll receive an invitation..."
```

### Tool Availability

Tools available to LLM for general questions:

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

## Decision Tree: Request Type Classification

```
╔═══════════════════════════════════════════╗
║ User Message in Chat                      ║
╚═════════════┬─────────────────────────────╝
              │
    ┌─────────┴─────────┐
    │                   │
    ▼                   ▼
Starts with   No prefix
"/"?           /intent?
│              │
│ YES          ▼
▼          CombinedIntent
COMMAND     ComplexityService
│
│          ┌──────┬────────┬──────────┬──────────────┬────────┐
│          │      │        │          │              │        │
│          ▼      ▼        ▼          ▼              ▼        ▼
│      create_ navigate_ create_  manage_  search_  general_
│      list    to_page  resource resource  data    question
│          │      │        │          │              │        │
│          ▼      ▼        ▼          ▼              ▼        ▼
│      Complex? Route    Collect  Execute  Search  LLM +
│       │       Page     Params   Op       DB      Tools
│    ┌──┴──┐
│  YES NO
│   │  │
│   ▼  ▼
└──→ Questions or Direct
     Create List
     │
     └──→ Final Response
```

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

### Simple List Test
```ruby
message = "Create a grocery list"
# Expected: List created immediately, no questions
```

### Complex List Test
```ruby
message = "Plan a roadshow across US cities"
# Expected: Questions form shown, awaiting user answers
```

### Nested List Test
```ruby
message = "Organize roadshow: NYC, Chicago, Boston"
# Expected: Main list created with 3 sub-lists
```

### Command Test
```ruby
message = "/search budget"
# Expected: Results returned in <1 second
```

### Navigation Test
```ruby
message = "Show users"
# Expected: Page navigates to /admin/users
```

### Resource Create Test
```ruby
message = "Create user alice@example.com"
# Expected: Ask for missing parameters
```

### General Question Test
```ruby
message = "How do I add team members?"
# Expected: LLM responds with helpful answer
```

---

## Related Documentation

- [CHAT_FLOW.md](./CHAT_FLOW.md) - Complete message flow
- [CHAT_MODEL_SELECTION.md](./CHAT_MODEL_SELECTION.md) - Why gpt-4.1-nano
- [CHAT_FEATURES.md](./CHAT_FEATURES.md) - Feature implementation guide
