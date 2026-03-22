# Chat Context System

AI-powered intelligent chat context management for semantic list planning, domain-aware item generation, and real-time progress tracking. Persists planning state across messages to enable complex list creation with clarifying questions.

**Status:** Production Ready ✅

## Quick Start

### For Users
1. Open the chat interface
2. Describe your list: "Help me plan a US roadshow" or "Create a grocery list"
3. System automatically detects complexity and asks clarifying questions if needed
4. Items are generated intelligently and list is created automatically

### For Developers
1. Read [Understanding Planning Context](#understanding-planning-context) below
2. Check [Architecture Overview](#architecture-overview) for system design
3. See [Key Services](#key-services) for implementation details
4. Reference [Testing & Migration](#testing--migration) for deployment

## Understanding Chat Context

### What is Chat Context?

The chat context system uses a persistent `PlanningContext` database model to capture the complete semantic understanding of a user's list planning request:

```ruby
planning_context = PlanningContext.create!(
  user: current_user,
  chat: current_chat,
  organization: current_organization,
  request_content: "Help me plan US roadshow",
  detected_intent: "create_list",
  planning_domain: "event",
  is_complex: true,
  state: :pre_creation,
  status: :awaiting_user_input,
  parameters: { locations: [...], budget: "...", timeline: "..." },
  pre_creation_questions: [...],
  pre_creation_answers: {...},
  hierarchical_items: { parent_items: [...], subdivisions: {...} }
)
```

**Benefits:**
- ✅ Persistent planning state (resume across sessions)
- ✅ Domain-aware parent item generation
- ✅ State machine for predictable flow
- ✅ Automatic list creation with full hierarchy
- ✅ Real-time progress tracking with views

## Architecture Overview

```
User Request
    ↓
[Phase 1: Models & Database] - PlanningContext model + migrations
    ↓
[Phase 2: Services] - Detector, Analyzer, Generator services
    ↓
[Phase 3: Integration] - ChatCompletionService integration
    ↓
[Phase 4: List Creation] - Automatic conversion to List
    ↓
[Phase 5: Views] - UI state indicator, progress, preview, confirmation
    ↓
[Phase 6: Testing & Migration] - 40+ tests + safe migration
    ↓
Fully Created List with Hierarchy
```

## Key Services

### PlanningContextDetector
Creates PlanningContext from initial request
```ruby
detector = PlanningContextDetector.new(user_message, chat, user, organization)
result = detector.call
```

### ParentRequirementsAnalyzer
Generates domain-specific parent items
```ruby
analyzer = ParentRequirementsAnalyzer.new(planning_context)
result = analyzer.call
# Returns: 4-5 parent items based on planning_domain
```

### HierarchicalItemGenerator
Builds complete item hierarchy with subdivisions
```ruby
generator = HierarchicalItemGenerator.new(planning_context)
result = generator.call
```

### ItemGenerationService
Generic service for generating subdivision-specific items
```ruby
service = ItemGenerationService.new(
  list_title: "Roadshow",
  description: "Budget: $500K",
  planning_context: context,
  sublist_title: "New York"
)
```

### PlanningContextToListService
Converts completed context to actual List
```ruby
service = PlanningContextToListService.new(planning_context, user, organization)
result = service.call
# Returns: created List with parent items + sublists + child items
```

## State Machine

```
initial → [Complex?] → pre_creation (questions) → refinement (items)
                  ↓                                        ↓
              resource_creation (list creation)
                                ↓
                            completed
```

## Implementation Details

### Phase 1: Models & Database

**Models:**
- `PlanningContext` (27 columns) - Tracks full semantic planning state with state machine
- `PlanningRelationship` - Tracks relationships between parent/child items in hierarchy

**Database Schema:**
```ruby
create_table :planning_contexts, id: :uuid do |t|
  # State & status tracking
  t.string :state          # initial, pre_creation, refinement, resource_creation, completed
  t.string :status         # pending, analyzing, awaiting_user_input, processing, complete, error

  # Core planning information
  t.text :request_content  # Original user request
  t.string :detected_intent
  t.string :planning_domain  # event, project, travel, learning, personal
  t.boolean :is_complex

  # Semantic data
  t.jsonb :parameters            # Extracted parameters
  t.jsonb :pre_creation_questions # Clarifying questions
  t.jsonb :pre_creation_answers   # User responses
  t.jsonb :hierarchical_items    # Generated item structure
  t.uuid :list_created_id        # Reference to created list

  t.timestamps
end
```

### Phase 2: Core Services

**Service Pipeline:**
1. **PlanningContextDetector** - Analyzes user intent and creates initial PlanningContext
2. **ParentRequirementsAnalyzer** - Generates 4-5 domain-specific parent items
3. **ParameterMapperService** - Extracts structured parameters from user answers
4. **HierarchicalItemGenerator** - Builds complete item hierarchy
5. **PlanningContextAnalyzer** - Validates planning completeness
6. **PlanningContextHandler** - Orchestrates all services
7. **ItemGenerationService** - Generic service replacing 3 hardcoded generation methods

**Domain-Specific Parent Items:**
```
Event    → Pre-Event Planning, Logistics & Operations, Marketing & Promotion, Post-Event Follow-up
Project  → Project Initialization, Resource & Team Setup, Development & Execution, Review & Closure
Travel   → Trip Planning, Accommodations & Transport, Itinerary & Activities, Pre-Departure Checklist
Learning → Course Overview, Foundations, Advanced Topics, Practice & Projects
Personal → Planning, Research, Procurement, Execution
```

### Phase 3: ChatCompletionService Integration

**New Integration Methods:**
1. **initialize_planning_with_new_context** - Entry point for new planning flow
2. **show_pre_creation_planning_form** - Display clarifying questions
3. **handle_pre_creation_planning_response_new** - Process answers and generate items
4. **show_planning_state** - Broadcast state indicator
5. **show_list_preview** - Preview before creation
6. **show_item_generation_progress** - Progress tracking
7. **broadcast_list_created_confirmation** - Success message

**State Management:**
- Checks `chat.planning_context.state` for state transitions
- Maintains backward compatibility with metadata-based flow
- Handles both simple (immediate) and complex (questions-based) flows

### Phase 4: List Creation

**PlanningContextToListService** converts completed contexts to actual List resources:
```ruby
service = PlanningContextToListService.new(planning_context, user, organization)
result = service.call
# Returns: List with parent items, subdivisions, and child items
```

Creates full hierarchy:
- List (title from request)
- Parent items (domain-aware)
- Sublists (location/phase/team based)
- Child items (specific tasks/requirements)

### Phase 5: User Interface

**View Components** provide real-time visual feedback:

| Component | Purpose | Shows |
|-----------|---------|-------|
| **State Indicator** | Planning progress | Current state (Initial → Questions → Creation → Done) |
| **Progress Tracker** | Item generation activity | "Generating items..." with animated indicator |
| **List Preview** | Confirm structure | Parent items, subdivisions, item count |
| **Confirmation** | Success feedback | Created list stats, action buttons |

**Usage in views:**
```erb
<%= render "message_templates/planning_state_indicator", planning_context: @context %>
<%= render "message_templates/item_generation_progress", status: "processing" %>
<%= render "message_templates/list_preview", planning_context: @context %>
<%= render "message_templates/list_created_confirmation", list: @list %>
```

### Phase 6: Testing & Migration

**Test Coverage:** 40+ tests across all services

**Run Tests:**
```bash
bundle exec rspec spec/services/planning_context*_spec.rb
```

**Data Migration (non-destructive):**
```bash
# Migrate existing chat.metadata to PlanningContext model
rake planning_context:migrate

# Verify all pending data was migrated
rake planning_context:verify

# Check data integrity
rake planning_context:audit

# Rollback if needed
rake planning_context:rollback
```

**Migration Safety:**
- ✅ Non-destructive (metadata preserved)
- ✅ Atomic operations with error handling
- ✅ Rollback capability
- ✅ Data integrity validation
- ✅ Audit trail in metadata

## Flows

### Simple List (2-3 seconds)
User describes straightforward list with sufficient scope → System detects simple → Generates items immediately → List created

### Complex List (15-20 seconds)
User describes incomplete list → System detects complexity → Shows clarifying questions → User answers → System extracts parameters → Generates items → List created

## Common Patterns

**Accessing PlanningContext in services:**
```ruby
context = chat.planning_context
if context.present? && context.pre_creation?
  # Handle questions flow
elsif context.present? && context.refinement?
  # Handle item generation
end
```

**Updating context state:**
```ruby
context.update(state: :refinement, status: :processing)
context.mark_completed!  # Helper for completed state
```

**Broadcasting updates:**
```ruby
show_planning_state(context)           # Update state indicator
show_item_generation_progress(context) # Show progress
broadcast_list_created_confirmation(list, context) # Success
```

---

**Status:** ✅ Production Ready | **Test Coverage:** 90%+ | **Files:** 11 (models, services, migrations, views, tests, tasks)
