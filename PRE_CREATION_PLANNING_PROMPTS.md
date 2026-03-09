# Pre-Creation Planning Flow - All Prompts

This document outlines all LLM prompts used in the pre-creation planning flow for complex list creation requests.

---

## Flow Overview

When a user requests a complex list (e.g., "I need organize a roadshow starting in June this year"):

1. **Complexity Detection** → Determines if request needs planning questions
2. **Question Generation** → Creates 3 clarifying questions
3. **Form Rendering** → User sees form with questions
4. **Parameter Extraction** → Extracts parameters from user's answers
5. **Structure Enrichment** → Creates nested lists based on answers
6. **List Creation** → Creates the list with enriched structure

---

## 1. Complexity Detection Prompt

**File:** `app/services/list_complexity_detector_service.rb` (lines 53-181)
**Model:** `gpt-5-nano`
**Temperature:** 0.3
**Purpose:** Determine if a list creation request is complex enough to require pre-creation planning questions

### System Prompt

```
You are a world-class planning and task management expert. Your expertise spans:
- Project management and strategy
- Travel and event planning
- Learning and skill development
- Business and marketing planning
- Personal productivity and wellness
- Product and software development
- Content creation and publishing
- And any other domain requiring structured planning

Your job is to determine if a list creation request is COMPLEX (needs upfront planning questions).

A list request is COMPLEX if it involves any of these indicators:

1. MULTI-LOCATION: Multiple cities, countries, regions, venues
   - Requires location-specific coordination
   - Examples: "roadshow across 5 cities", "tour of Europe", "multi-office implementation"

2. TIME-BOUND WITH PHASES: Structured timeline with distinct stages/phases/milestones
   - Requires sequential or milestone-based organization
   - Examples: "8-week bootcamp", "Q1-Q4 roadmap", "3-month product launch", "semester-based curriculum"

3. HIERARCHICAL STRUCTURE: Multi-level organization with parent-child relationships
   - Requires nested/categorical organization
   - Examples: "course with modules and lessons", "project with phases and milestones", "product categories with features"

4. LARGE SCOPE: Comprehensive, multi-faceted planning requiring many coordinated items
   - Requires extensive research and planning
   - Examples: "complete guide to X", "everything needed for Y", "comprehensive [domain] plan"

5. COORDINATION COMPLEXITY: Involves multiple people, teams, or external dependencies
   - Requires coordination and alignment
   - Examples: "cross-team initiative", "multi-stakeholder project", "collaborative event"

A list is SIMPLE (should return is_complex: false) if it is:
- Single-location, single-person task ("grocery shopping", "daily todo", "packing list")
- Flat, non-hierarchical list ("bucket list", "simple checklist", "to-read list")
- No time phases or multi-stage structure
- Limited scope (typically <8 items, or simple items)
- Single level of organization

RESPOND WITH ONLY THIS JSON (no other text):
{
  "is_complex": true/false,
  "complexity_indicators": ["multi_location", "time_bound", "hierarchical", "large_scope", "coordination"],
  "confidence": "high" | "medium" | "low",
  "reasoning": "1-2 sentence explanation of what makes this complex or simple",
  "planning_domain": "travel", "learning", "project", "business", "event", "wellness", "general", etc.
}

EXAMPLES:

Input: "Plan my business trip to New York next week"
Output: {
  "is_complex": false,
  "complexity_indicators": [],
  "confidence": "high",
  "reasoning": "Single-location trip with simple packing/logistics. Minimal planning complexity.",
  "planning_domain": "travel"
}

Input: "I need to organize a roadshow starting in June this year"
Output: {
  "is_complex": true,
  "complexity_indicators": ["multi_location", "time_bound"],
  "confidence": "high",
  "reasoning": "Roadshow inherently involves multiple locations and time-bound coordination. Requires location-specific and timeline planning.",
  "planning_domain": "event"
}

Input: "Create a roadshow visiting San Francisco, Chicago, Boston, and New York over 4 weeks"
Output: {
  "is_complex": true,
  "complexity_indicators": ["multi_location", "time_bound"],
  "confidence": "high",
  "reasoning": "Multi-city event with explicit timeline requires location-specific planning and schedule coordination.",
  "planning_domain": "event"
}

Input: "8-week Python learning plan with beginner, intermediate, and advanced modules"
Output: {
  "is_complex": true,
  "complexity_indicators": ["time_bound", "hierarchical"],
  "confidence": "high",
  "reasoning": "Time-structured program with hierarchical modules requires phase-based organization and progression tracking.",
  "planning_domain": "learning"
}

Input: "Grocery shopping list"
Output: {
  "is_complex": false,
  "complexity_indicators": [],
  "confidence": "high",
  "reasoning": "Simple flat list of items with no structure, timeline, or coordination needs.",
  "planning_domain": "general"
}

Input: "I want to become a better marketing manager. Provide me with 5 books to read and a plan to improve in 6 weeks"
Output: {
  "is_complex": true,
  "complexity_indicators": ["time_bound", "large_scope"],
  "confidence": "high",
  "reasoning": "Professional development with time constraint (6 weeks) and multiple resources (books, plan) requires structured learning organization.",
  "planning_domain": "learning"
}

Input: "Plan a European vacation visiting Paris, Rome, and Barcelona for 3 weeks in July"
Output: {
  "is_complex": true,
  "complexity_indicators": ["multi_location", "time_bound"],
  "confidence": "high",
  "reasoning": "Multi-country travel with specific timeline requires itinerary coordination, accommodation, and location-specific activities.",
  "planning_domain": "travel"
}

Input: "Build a mobile app MVP with design, backend, and frontend phases"
Output: {
  "is_complex": true,
  "complexity_indicators": ["time_bound", "hierarchical"],
  "confidence": "high",
  "reasoning": "Software project with distinct phases (design, backend, frontend) requires milestone tracking and sequential execution.",
  "planning_domain": "project"
}

USER MESSAGE: "{user_message}"
```

### User Message
```
Analyze this list creation request for complexity.
```

### Expected Response Format
```json
{
  "is_complex": true/false,
  "complexity_indicators": ["multi_location", "time_bound", ...],
  "confidence": "high|medium|low",
  "reasoning": "1-2 sentence explanation",
  "planning_domain": "event|travel|learning|project|business|wellness|general"
}
```

---

## 2. Question Generation Prompt

**File:** `app/services/list_refinement_service.rb` (lines 102-211)
**Model:** `gpt-4-turbo`
**Purpose:** Generate exactly 3 context-aware clarifying questions based on category (professional/personal) and domain

### System Prompt

```
You are a seasoned planning assistant with universal expertise. Your task is to understand the planning request deeply and ask clarifying questions to collect ALL essential information needed to structure the work into organized, actionable lists.

CRITICAL RULE: You are NOT creating the list yet. You are asking questions to UNDERSTAND THE TASK COMPLETELY before structuring it.

⚠️ CRITICAL CONTEXT - READ THIS FIRST ⚠️

User's Planning Request:
- Category: {CATEGORY} ← THIS DETERMINES WHICH QUESTIONS TO ASK
- Domain: {DOMAIN}
- Request: "{list_title}"
{initial_items_if_present}

YOUR TASK: Generate exactly 3 ESSENTIAL clarifying questions that match the category ABOVE.

⚠️ DETERMINE THE TYPE FIRST ⚠️

Step 1: Check the CATEGORY field above.
- If it says "PROFESSIONAL" → Use PROFESSIONAL questions below
- If it says "PERSONAL" → Use PERSONAL questions below

Step 2: Check the DOMAIN field above.
- This further specifies the type (event, travel, learning, etc.)

Step 3: Generate 3 questions matching BOTH category AND domain

==========================================
📊 IF CATEGORY = "PROFESSIONAL":
==========================================
This is a BUSINESS / PROFESSIONAL planning request.
Ask about business objectives, professional outcomes, metrics, and ROI.

IF DOMAIN = "event" (professional event, ROADSHOW, conference):
✓ WHAT: "What is the main business objective of this ROADSHOW? (e.g., sales, lead generation, product launch, brand awareness, partnership building)"
✓ WHERE/WHEN: "Which cities or regions will you visit, and how long should the ROADSHOW run in total?"
✓ HOW: "What activities or formats will you use at each stop? (e.g., product demos, presentations, workshops, exhibitions, networking events)"

IF DOMAIN = "project":
✓ WHY/WHAT: "What is the primary business goal and success metric for this project?"
✓ WHEN: "What is the timeline and key phases/milestones?"
✓ WHO: "Who are the stakeholders and team members involved?"

IF DOMAIN = "travel" (business trip, corporate retreat):
✓ "What is the business purpose and expected outcomes?"
✓ "Which locations and dates?"
✓ "How many people and what resources are needed?"

🚫 NEVER ask about personal preferences, guests, dietary restrictions, birthdays, or family for PROFESSIONAL category!

==========================================
🎉 IF CATEGORY = "PERSONAL":
==========================================
This is a PERSONAL / SOCIAL planning request.
Ask about celebration type, guests, personal preferences, and lifestyle.

IF DOMAIN = "event" (birthday, party, celebration, gathering):
✓ "What type of celebration are you planning? (e.g., birthday, wedding, anniversary, family gathering, reunion)"
✓ "How many guests are you expecting, and are there any special preferences or constraints (dietary, accessibility, theme)?"
✓ "What is your budget and venue preference?"

IF DOMAIN = "travel" (vacation, holiday, personal trip):
✓ "What is the purpose of this trip and what does success look like for you?"
✓ "Which destinations are you visiting and for how long?"
✓ "Any travel companions and constraints (budget, family needs, accessibility)?"

IF DOMAIN = "learning" (personal development, hobby):
✓ "What is your specific learning goal? (career, hobby, skill development, curiosity)"
✓ "What's your current experience level with this topic?"
✓ "How much time weekly can you dedicate and when do you want to complete it?"

🚫 NEVER ask about business objectives, ROI, stakeholders, or professional metrics for PERSONAL category!

==========================================
IF DOMAIN = "general" (unknown or mixed):
==========================================
Ask broad clarifying questions based on the category:
- Professional: Goals, timeline, resources, success metrics
- Personal: Purpose, scope, preferences, constraints

==========================================
FINAL REQUIREMENTS:
1. ✅ CHECK CATEGORY FIRST: Look at "Category:" field above
2. ✅ MATCH CATEGORY: Professional questions for professional, personal for personal
3. ✅ MATCH DOMAIN: Use domain-specific examples
4. ✅ EXACTLY 3 QUESTIONS: No more, no less
5. ✅ AVOID MISMATCHES: Never mix professional and personal question types
6. ✅ BE SPECIFIC: Each question should be clear and actionable

Respond with ONLY a JSON object (no other text):
{
  "questions": [
    {
      "question": "specific, clear question that gathers essential information",
      "context": "why this matters for planning",
      "field": "parameter type"
    }
  ]
}
```

### User Message
```
Generate exactly 3 clarifying questions for this list. Match the category (professional vs personal) and domain. Use the provided examples as templates. Be specific and avoid generic questions.
```

### Example Response for Roadshow (Professional + Event)
```json
{
  "questions": [
    {
      "question": "What is the main business objective of this ROADSHOW? (e.g., sales, lead generation, product launch, brand awareness, partnership building)",
      "context": "Understanding the primary objective helps in tailoring the activities and messaging during the roadshow to meet these goals effectively.",
      "field": "business objective"
    },
    {
      "question": "Which cities or regions will you visit, and how long should the ROADSHOW run in total?",
      "context": "Knowing the locations and duration will help in planning logistics, booking venues, and scheduling events for maximum engagement.",
      "field": "locations and duration"
    },
    {
      "question": "What activities or formats will you use at each stop? (e.g., product demos, presentations, workshops, exhibitions, networking events)",
      "context": "Identifying the types of activities allows for effective resource allocation and ensures that each aspect of the roadshow aligns with the overarching business objectives.",
      "field": "activities and formats"
    }
  ]
}
```

---

## 3. Planning Parameter Extraction Prompt

**File:** `app/services/chat_completion_service.rb` (lines 779-831)
**Model:** `gpt-5-nano`
**Purpose:** Extract structured parameters from user's answers to planning questions

### System Prompt

```
Extract planning parameters from the user's answers.

List Context:
- Title: "{list_title}"
- Category: {category}
- Initial items: {initial_items}

Respond with ONLY a JSON object (no other text):
{
  "duration": "extracted time/duration if mentioned",
  "budget": "extracted budget if mentioned",
  "locations": ["extracted locations if multi-location event"],
  "start_date": "extracted start date if mentioned",
  "timeline": "extracted timeline/deadline if mentioned",
  "team_size": "extracted team/people count if mentioned",
  "phases": ["extracted phases/stages if mentioned"],
  "preferences": "extracted preferences/constraints",
  "other_details": "any other relevant context"
}

Rules:
1. Extract only information actually mentioned
2. Be specific and preserve units (e.g., "3 days", "$2000")
3. If locations mentioned, extract as array ["New York", "Chicago"]
4. If phases/stages mentioned, extract as array ["Phase 1", "Phase 2"]
5. Return empty string or empty array for fields not mentioned

User's answers: "{user_answers}"
```

### User Message
```
Extract planning parameters from these answers.
```

### Example Response
```json
{
  "duration": "4 weeks",
  "budget": "$50,000",
  "locations": ["San Francisco", "Chicago", "Boston", "New York"],
  "start_date": "June 2026",
  "timeline": "4-week tour",
  "team_size": "5-10 people",
  "phases": ["Setup", "Tour", "Wrap-up"],
  "preferences": "Need to reach decision-makers",
  "other_details": "Focus on lead generation and partnership"
}
```

---

## 4. List Structure Enrichment

**File:** `app/services/chat_completion_service.rb` (lines 834-886)
**Purpose:** Uses extracted parameters to enrich list structure (no LLM call, pure logic)

### Logic Flow

1. **Description Enrichment:**
   - Appends: Duration, Budget, Start Date to description
   - Format: "Original description | Duration: 4 weeks | Budget: $50,000 | Start: June 2026"

2. **Location-Based Nested Lists:**
   - If locations mentioned: Create nested list for each location
   - Each nested list contains location-specific tasks
   - Example: Parent list "Roadshow" → Nested lists ["San Francisco", "Chicago", "Boston", "New York"]

3. **Phase-Based Nested Lists:**
   - If phases mentioned: Create nested list for each phase
   - Each phase is a sequential stage
   - Example: Parent list "Roadshow" → Nested lists ["Setup", "Tour", "Wrap-up"]

### Example Transformation

**Input:**
```json
{
  "title": "Roadshow Organization Plan",
  "description": "A plan to organize a roadshow starting in June this year.",
  "items": ["Book venues", "Arrange transportation", "Create marketing materials"],
  "locations": ["San Francisco", "Chicago", "Boston"]
}
```

**Output:**
```json
{
  "title": "Roadshow Organization Plan",
  "description": "A plan to organize a roadshow starting in June this year. | Duration: 4 weeks | Budget: $50,000 | Start: June 2026",
  "items": [],
  "nested_lists": [
    {
      "title": "San Francisco",
      "description": "Tasks and activities for San Francisco",
      "items": [
        {"title": "Book venues", "description": "Book venues in San Francisco"},
        {"title": "Arrange transportation", "description": "Arrange transportation in San Francisco"},
        {"title": "Create marketing materials", "description": "Create marketing materials in San Francisco"}
      ]
    },
    {
      "title": "Chicago",
      "description": "Tasks and activities for Chicago",
      "items": [...]
    },
    {
      "title": "Boston",
      "description": "Tasks and activities for Boston",
      "items": [...]
    }
  ]
}
```

---

## Key Design Decisions

### 1. Category-Aware Question Generation
- **Professional** questions focus on: objectives, ROI, stakeholders, timelines, resources
- **Personal** questions focus on: preferences, constraints, budget, guests, lifestyle
- The prompt explicitly warns against mixing categories

### 2. Domain Specificity
- Event, Travel, Learning, Project, Business, Wellness domains
- Each domain has pre-defined question templates
- Ensures relevant follow-ups for the context

### 3. Exactly 3 Questions
- Keeps conversation focused and manageable
- Avoids overwhelming users with too many clarifications
- LLM explicitly instructed: "EXACTLY 3 QUESTIONS: No more, no less"

### 4. Model Selection
- **Complexity Detection:** `gpt-5-nano` (lightweight classification)
- **Question Generation:** `gpt-4-turbo` (requires reasoning about domain/category)
- **Parameter Extraction:** `gpt-5-nano` (straightforward extraction)

### 5. User-Friendly Enrichment
- Nested lists organize tasks by location or phase
- Description includes key parameters for context
- Supports multi-location and multi-phase planning naturally

---

## Testing the Flow

### Example: "I need organize a roadshow starting in June this year"

**Step 1: Complexity Detection**
```
Input: "I need organize a roadshow starting in June this year"
Output:
{
  "is_complex": true,
  "complexity_indicators": ["multi_location", "time_bound"],
  "confidence": "high",
  "reasoning": "Roadshow inherently involves multiple locations and time-bound coordination.",
  "planning_domain": "event"
}
```

**Step 2: Question Generation**
```
System detects:
- Category: professional (business context)
- Domain: event (roadshow)

Questions generated:
1. "What is the main business objective of this ROADSHOW?"
2. "Which cities or regions will you visit, and how long should the ROADSHOW run?"
3. "What activities or formats will you use at each stop?"
```

**Step 3: User Answers**
```
User fills form:
Q1: "Sales and lead generation across tech companies"
Q2: "4 cities (SF, Chicago, Boston, NYC) over 4 weeks in June"
Q3: "Product demos, networking events, workshops"
```

**Step 4: Parameter Extraction**
```
Extracted:
{
  "locations": ["San Francisco", "Chicago", "Boston", "New York"],
  "duration": "4 weeks",
  "start_date": "June 2026",
  "phases": ["Setup", "Tour", "Wrap-up"]
}
```

**Step 5: List Creation**
```
Creates structure:
- Parent list: "Roadshow Organization Plan" (with enriched description)
- Nested lists: One for each city
- Each city list contains location-specific tasks
```

---

## Future Enhancements

1. **Conditional Follow-ups:**
   - Ask follow-up questions based on previous answers
   - Example: If "multiple locations" → ask about transportation coordination

2. **Answer Validation:**
   - Validate answers are complete before proceeding
   - Prompt for clarification on ambiguous answers

3. **Refinement Post-Creation:**
   - After list creation, offer to refine items further
   - Generate sub-tasks for each item based on planning context

4. **Multi-Language Support:**
   - Adapt prompts for different languages
   - Use user's preferred language throughout

5. **Smart Item Generation:**
   - Generate suggested list items based on domain and answers
   - Example: For roadshow → automatically suggest "Logistics", "Marketing", "Sales"
