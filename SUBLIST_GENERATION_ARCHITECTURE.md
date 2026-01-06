# Flexible Sublist Generation Architecture

## Overview

The pre-creation planning system now intelligently generates context-aware items for nested sublists. Each sublist gets unique, tailored actions instead of generic copies or empty lists.

The system supports:
- **Location-based subdivisions** (multi-city roadshows, tours, regional events)
- **Phase/stage subdivisions** (time-based: weeks, months, phases, chapters)
- **Generic context-aware subdivisions** (any other type the LLM can infer)

## Core Philosophy

> "Each sublist should have actions specific to its context, not duplicates or empty placeholders."

**Examples:**
- **Roadshow in 3 cities**: San Francisco sublist gets SF-specific tasks (SF venues, SF logistics, SF marketing), different from Chicago and Boston
- **Learning in 6 weeks**: Week 1 focuses on fundamentals and setup, Week 2 on core concepts, Week 3 on practice, Week 4+ on progressive complexity
- **Project with phases**: Planning phase has research and planning tasks, Execution has implementation tasks, Wrap-up has delivery and documentation tasks

## Architecture

### 1. Flow Overview

```
User Request
    ↓
Complexity Detection (is_complex?)
    ↓
Question Generation (ask planning questions)
    ↓
Form Submission (user answers questions)
    ↓
Parameter Extraction (extract locations, phases, budget, etc.)
    ↓
Structure Enrichment (generate context-aware sublists)
    ↓
List Creation (create parent + smart sublists)
```

### 2. Key Components

#### **Parameter Extraction** (`extract_planning_parameters_from_answers`)
- Extracts structured data from user's free-form answers
- Uses gpt-5-nano for efficiency
- Identifies:
  - `locations`: Multi-location event subdivisions
  - `phases`: Time-based/sequential subdivisions (weeks, phases, chapters, modules)
  - `duration`, `budget`, `start_date`, `timeline`, `team_size`
  - `preferences`, `other_details`

#### **Subdivision Type Detection** (`determine_subdivision_type`)
- Determines which type of subdivision to use
- Priority order:
  1. **Locations** (if multi-location event)
  2. **Phases** (if time-based/sequential plan)
  3. **Other** (for any other subdivision type)
  4. **None** (if no subdivisions detected)

#### **Item Generation Methods**

**1. Location-Specific Items** (`generate_location_specific_items`)
- For multi-city roadshows, tours, regional events
- Generates tasks unique to each location
- Considers:
  - Local venue and logistics
  - Regional regulations and permits
  - Local market conditions
  - Transportation and accommodation
  - Time zones
  - Local partnerships
  - Regional customizations
- Example output for "San Francisco":
  ```
  [
    "Scout and book venue in San Francisco",
    "Arrange local transportation and accommodations",
    "Coordinate with SF-based speakers",
    "Plan SF market-specific marketing campaign",
    "Arrange SF-specific catering and logistics",
    "Schedule post-event feedback in SF"
  ]
  ```

**2. Phase-Specific Items** (`generate_phase_specific_items`)
- For time-based/sequential plans (weeks, phases, stages)
- Generates tasks unique to each phase
- Emphasizes:
  - Primary goal of this phase
  - Key activities unique to this phase
  - Dependencies on previous phases
  - Deliverables for this phase
  - Phase-specific risks/challenges
- Example for 6-week learning plan:
  - **Week 1**: Fundamentals setup, environment configuration
  - **Week 2**: Core concepts, foundational knowledge
  - **Week 3**: Deeper practice, building blocks
  - **Week 4**: Intermediate topics, small projects
  - **Week 5**: Advanced topics, capstone project
  - **Week 6**: Consolidation, assessment, review

**3. Context-Aware Items** (`generate_context_aware_items`)
- For any other subdivision type
- Flexible method that adapts to the context
- Considers progression and unique aspects of each section
- Supports chapters, modules, parts, or any other subdivision

#### **Structure Enrichment** (`enrich_list_structure_with_planning`)
- Converts flat base structure into nested hierarchy
- Keeps parent list items (general/cross-cutting tasks)
- Creates sublists with LLM-generated context-specific items
- Flow:
  ```ruby
  case subdivision_type
  when :locations
    # Create sublist for each location
    # Populate with location-specific items
  when :phases
    # Create sublist for each phase
    # Populate with phase-specific items (showing progression)
  when :other
    # Create sublist for each item in list
    # Populate with context-aware items
  end
  ```

### 3. Prompt Design

All generation prompts follow a consistent pattern:

#### **Structure**
1. **Role and task**: "You are a planning assistant. Generate tasks for..."
2. **Context**: Plan title, current subdivision, base items, budget, duration, domain
3. **Critical instruction**: "Generate tasks that are SPECIFIC and DIFFERENT, not generic copies"
4. **Consideration factors**: What makes this subdivision unique
5. **Constraints**: Avoid duplication, focus on specific aspects
6. **Output format**: JSON array only, no other text

#### **Key Instruction**
All prompts include:
```
IMPORTANT: Generate tasks that are SPECIFIC and DIFFERENT for [this location/phase/section].
Each [location/phase/section] has unique needs, constraints, and activities.
Avoid duplicating base items - focus on [location/phase/section]-specific considerations.
```

This explicitly prevents the LLM from generating duplicate tasks across sublists.

#### **Context Provision**
All prompts include:
- Base plan title
- Current subdivision identifier (location name, phase number, etc.)
- Base items (general tasks for reference)
- Budget and duration
- Planning domain
- Previous phase context (for phase-based plans)

### 4. Result Structure

**Parent List:**
```json
{
  "title": "6-Week Learning Plan",
  "description": "Learn Python in 6 weeks | Duration: 6 weeks",
  "items": [
    "Choose learning resources",
    "Set up development environment",
    "Create practice project",
    "Track progress weekly",
    "Review and consolidate"
  ],
  "nested_lists": [...]
}
```

**Sublists (Phase-Based Example):**
```json
[
  {
    "title": "Week 1",
    "description": "Phase 1 of 6",
    "items": [
      "Install Python and IDE",
      "Learn syntax and basic data types",
      "Understand variables and operators",
      "Write first hello-world program",
      "Complete syntax exercises"
    ]
  },
  {
    "title": "Week 2",
    "description": "Phase 2 of 6",
    "items": [
      "Study control flow (if/else/loops)",
      "Learn functions and parameters",
      "Understand scope and namespaces",
      "Build simple calculator program",
      "Practice with problems on HackerRank"
    ]
  },
  ...
]
```

**Sublists (Location-Based Example):**
```json
[
  {
    "title": "San Francisco",
    "description": "Tasks and activities for San Francisco",
    "items": [
      "Scout and book venue in San Francisco",
      "Arrange local transportation from airport to venue",
      "Coordinate with SF-based tech company speakers",
      "Plan SF market-specific marketing campaign",
      "Arrange catering with SF vendors"
    ]
  },
  {
    "title": "Chicago",
    "description": "Tasks and activities for Chicago",
    "items": [
      "Scout and book venue in Chicago",
      "Arrange local transportation from Chicago O'Hare",
      "Coordinate with Chicago-based financial sector speakers",
      "Plan Chicago market-specific marketing campaign",
      "Arrange catering with Chicago vendors"
    ]
  }
]
```

## Examples

### Example 1: Roadshow Planning

**User Request:** "Plan a roadshow for 3 cities in Q1"

**Questions Asked:**
1. Which cities are you planning to visit?
2. What's your total budget for this roadshow?
3. When in Q1 would you like to start?

**User Answers:**
```
Cities: San Francisco, Chicago, Boston
Budget: $150,000
Start: January 15, 2025
```

**Extraction:**
- locations: ["San Francisco", "Chicago", "Boston"]
- duration: "Q1"
- budget: "$150,000"
- start_date: "January 15, 2025"

**Result:**
- Parent list: "Roadshow Q1" with general items (Choose venues, Create budget, Hire speakers, Design materials, etc.)
- SF sublist: SF-specific items (Book SF venue, SF logistics, SF marketing, etc.)
- Chicago sublist: Chicago-specific items (different venues, logistics, partners)
- Boston sublist: Boston-specific items (different again)

### Example 2: Learning Plan

**User Request:** "I want to learn React in 6 weeks"

**Questions Asked:**
1. What's your current experience level?
2. What projects do you want to build?
3. How many hours per week can you dedicate?

**User Answers:**
```
Level: Intermediate JavaScript, new to React
Projects: Todo app, weather app, portfolio site
Hours: 15-20 per week
```

**Extraction:**
- phases: ["Week 1", "Week 2", "Week 3", "Week 4", "Week 5", "Week 6"]
- duration: "6 weeks"
- team_size: "1 (self-paced)"
- preferences: "project-based learning"

**Result:**
- Parent list: "Learn React" with general items (Setup environment, Review fundamentals, etc.)
- Week 1 sublist: Foundation tasks (JSX basics, components, props)
- Week 2 sublist: State management (useState, useEffect)
- Week 3 sublist: Advanced hooks (useReducer, useContext)
- Week 4 sublist: First project (Todo app)
- Week 5 sublist: More projects (weather app)
- Week 6 sublist: Capstone (portfolio site)

### Example 3: Event Planning

**User Request:** "Organize a corporate conference for 500 people"

**Questions Asked:**
1. When and where will the conference take place?
2. How many days is the conference?
3. What's the expected budget?

**User Answers:**
```
Date/Location: June 15-17 in New York
Days: 3 days
Budget: $200,000
```

**Extraction:**
- phases: ["Pre-Conference (May)", "During Conference (June 15-17)", "Post-Conference (June 18+)"]
- duration: "3 months planning, 3 days event"
- budget: "$200,000"
- start_date: "June 15, 2025"

**Result:**
- Parent list: "Corporate Conference" with general items
- Pre-Conference sublist: Planning, speaker coordination, marketing, logistics
- During Conference sublist: Day-of operations, setup, check-in, sessions
- Post-Conference sublist: Follow-up, feedback collection, reporting, archiving

## Error Handling

**JSON Parsing Failure:**
- If LLM response doesn't contain valid JSON array, return empty array `[]`
- Sublist still created with empty items (user can add manually)
- Error logged for monitoring

**LLM API Failures:**
- If API call fails, catch exception and return empty array
- System continues gracefully
- User can manually add items to empty sublist

**Invalid Subdivision Type:**
- If no locations, phases, or other items detected
- No nested lists created
- Parent list created with base items

## Configuration & Customization

### Change Model
```ruby
# Location items generation
llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4-turbo")

# Phase items generation
llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4-turbo")

# Context-aware items generation
llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4-turbo")
```

### Adjust Item Count
In prompts, change "4-6 specific, actionable tasks" to desired count.

### Add New Context Type
1. Update `extract_planning_parameters_from_answers` to recognize new type
2. Add method `generate_[type]_specific_items` with appropriate prompt
3. Update `determine_subdivision_type` to return `:new_type`
4. Add `when :new_type` case in `enrich_list_structure_with_planning`

## Testing Scenarios

### Scenario 1: Location-Based Roadshow
```
Input: "Plan a 4-city tour (SF, LA, NYC, Boston) in 3 months"
Expected: 4 sublists with location-specific items
Verify: Each city has unique tasks (venues, logistics, local speakers)
```

### Scenario 2: Time-Based Learning
```
Input: "Learn Python in 8 weeks with projects"
Expected: 8 sublists (Week 1-8) with progressive complexity
Verify: Week 1 fundamentals, Week 8 capstone/assessment
```

### Scenario 3: Phase-Based Project
```
Input: "Implement a mobile app in 4 phases"
Expected: 4 sublists with phase-specific deliverables
Verify: Planning → Design → Development → Testing/Launch
```

### Scenario 4: Complex Multi-Dimension
```
Input: "Organize conference in 3 cities"
Expected: 3 location sublists (locations take precedence)
Each with city-specific tasks
```

## Performance Considerations

- **Parallel Item Generation**: Could batch LLM requests for multiple sublists
- **Caching**: Cache location/phase prompts for repeated plans
- **Token Usage**: Each generation uses ~100-200 tokens via gpt-4-turbo
- **Latency**: ~2-3 seconds per sublist (can be parallelized)

## Future Enhancements

1. **Multi-dimensional sublists**: Both locations AND phases (matrix structure)
2. **Item dependency tracking**: Track which items depend on others
3. **Hierarchical depth**: Support nested lists within nested lists
4. **Template-based generation**: Pre-built templates for common scenarios
5. **Collaborative refinement**: Let users refine generated items
6. **Domain-specific intelligence**: Learn from domain patterns over time

## File References

- **Service**: `app/services/chat_completion_service.rb`
  - `enrich_list_structure_with_planning` (lines 834-916)
  - `generate_location_specific_items` (lines 918-953)
  - `generate_phase_specific_items` (lines 955-1025)
  - `generate_context_aware_items` (lines 1027-1076)
  - `determine_subdivision_type` (lines 1078-1090)
  - `extract_planning_parameters_from_answers` (lines 779-831)

- **Template**: `app/views/message_templates/_pre_creation_planning.html.erb`

- **Controller**: `app/javascript/controllers/pre_creation_planning_controller.js`

---

**Last Updated:** 2026-01-05
**Version:** 2.0
**Status:** Production Ready - Supports flexible, context-aware sublist generation
