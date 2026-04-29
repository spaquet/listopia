# Domain-Agnostic Architecture

## Critical Principle

**Listopia is NOT domain-specific.** While test cases and documentation examples may repeatedly use events (roadshows, vacations) for clarity, the entire system is architecturally generic and works equally well for ANY type of list, task, or planning domain.

This document explains how the system achieves this generality and where domain-specific logic is strictly forbidden.

## What "Domain-Agnostic" Means

The system makes NO assumptions about:
- What type of list the user is creating (event, course, recipe, project, etc.)
- How items should be subdivided (locations, books, modules, phases, topics, etc.)
- What parent items are relevant (these are generated per-request based on detected domain)
- What child items are appropriate for each subdivision

Instead, the system uses LLM reasoning to **detect** and **adapt** to whatever the user is planning.

## Architecture Components

### 1. CombinedIntentComplexityService ✅ GENERIC
- Detects if request is "simple" or "complex"
- Identifies planning domain dynamically (not hardcoded)
- **NOT domain-specific** - works the same for all domains

### 2. ParameterMapperService ✅ GENERIC
- Extracts parameters from user input and LLM-parsed answers
- **LLM-based subdivision detection** (NOT hardcoded rules)
- Detects best subdivision type for each specific request
- Examples:
  - Roadshow request → detects "locations" as subdivision
  - Reading list request → detects "books" as subdivision
  - Course request → detects "modules" as subdivision
  - Any other domain → LLM determines appropriate subdivision

### 3. ParentRequirementsAnalyzer ✅ GENERIC
- Generates parent items dynamically based on detected planning domain
- **NOT hardcoded lists** - analyzes request context
- Examples:
  - For event planning: generates "Pre-Event Planning", "Logistics", "Marketing", etc.
  - For course planning: generates "Prerequisites", "Curriculum Setup", "Assessment", etc.
  - For recipe planning: generates appropriate cooking stages
  - For any domain: LLM generates relevant parent items

### 4. HierarchicalItemGenerator ✅ GENERIC
- Creates subdivisions based on LLM-detected subdivision type
- **Fully generic** - works with any subdivision type
- For each subdivision, calls ItemGenerationService
- Supports any number of subdivisions (locations, books, modules, etc.)

### 5. ItemGenerationService ✅ GENERIC
- Generates items specific to each subdivision
- Receives `subdivision_type` parameter (NOT hardcoded)
- Uses LLM to generate context-appropriate items
- Examples:
  - For location-based roadshow: generates location-specific event items
  - For book-based reading list: generates reading activity items per book
  - For module-based course: generates learning objective items per module
  - For any subdivision: generates relevant items

## Where Domain-Specific Code is FORBIDDEN

❌ **DO NOT add:**
- Hardcoded domain checks: `if planning_domain == "event"`
- Hardcoded subdivision types: `case subdivision_type when "locations" ...`
- Hardcoded parent item lists: `ROADSHOW_PARENT_ITEMS = [...]`
- Hardcoded item generation rules: `case domain when "event" then generate_event_items`

✅ **INSTEAD:**
- Use LLM to detect subdivision type dynamically
- Use LLM to generate parent items based on context
- Use LLM to generate child items based on subdivision type
- Let services handle the generality

## Testing Considerations

**Important Note**: Test data may repeatedly use "roadshow" or "vacation" examples because they're easy to explain. This does NOT mean the system is event-specific.

When adding tests:
- Test with examples from different domains
- Example domains for tests:
  - Event planning: "Plan a roadshow", "Organize a conference"
  - Course creation: "Create a machine learning course", "Design a yoga program"
  - Reading lists: "Reading list on AI", "Books about productivity"
  - Project management: "Product launch", "Team migration"
  - Cooking: "Plan a dinner party", "Create recipe collection"
  - Travel: "Plan a trip to Europe", "Design itinerary"
  - Personal development: "Learning plan", "Career development"
  - Business: "Marketing campaign", "Sales process"

The tests should demonstrate that the same generic architecture works for all domains, not that the system is hardcoded for a specific domain.

## How to Add New Features Generically

### When Adding Item Generation Features
1. Don't ask "what domain is this for?"
2. Instead: Make it work for ANY domain
3. Use LLM to understand context
4. Generate items appropriate to that context

### When Adding Subdivision Support
1. Don't hardcode "locations" or "phases"
2. Instead: Let LLM detect the subdivision type
3. Make the subdivision generation logic generic
4. Verify it works with multiple domain examples

### When Adding Parent Item Generation
1. Don't hardcode items per domain
2. Instead: Analyze the planning context
3. Use LLM to generate relevant parent items
4. Support any domain equally

## Verification Checklist

Before submitting code:
- [ ] Does this feature work only for one domain? If yes, make it generic
- [ ] Are there hardcoded domain checks? If yes, remove them
- [ ] Does the code assume a specific subdivision type? If yes, make it flexible
- [ ] Would this feature work equally for reading lists, courses, recipes, projects? If no, refactor

## References

- [ITEM_GENERATION.md](ITEM_GENERATION.md) - Generic item generation
- [CHAT_CONTEXT.md](CHAT_CONTEXT.md) - Domain-agnostic planning context
- [CHAT_FLOW.md](CHAT_FLOW.md) - Generic flow for all request types
- [PARAMETER_MAPPER_SERVICE](../app/services/parameter_mapper_service.rb) - LLM-based subdivision detection
- [HIERARCHICAL_ITEM_GENERATOR](../app/services/hierarchical_item_generator.rb) - Generic subdivision generation
