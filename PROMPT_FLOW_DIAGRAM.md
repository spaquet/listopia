# Pre-Creation Planning Prompt Flow Diagram

## Visual Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         USER INPUT                                       │
│                                                                           │
│  "I need organize a roadshow starting in June this year"                 │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  1. COMPLEXITY DETECTION (ListComplexityDetectorService)                │
│  Model: gpt-5-nano | Temp: 0.3                                           │
│                                                                           │
│  Input: User message                                                      │
│  Prompt: "Is this complex planning request?"                              │
│                                                                           │
│  Analyzes for:                                                            │
│  • Multi-location (roadshow = YES)                                        │
│  • Time-bound phases (June timeline = YES)                                │
│  • Hierarchical structure                                                 │
│  • Large scope                                                            │
│  • Coordination complexity                                                │
│                                                                           │
│  Output JSON:                                                             │
│  {                                                                        │
│    "is_complex": true,                                                    │
│    "complexity_indicators": ["multi_location", "time_bound"],             │
│    "confidence": "high",                                                  │
│    "planning_domain": "event"                                             │
│  }                                                                        │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                    ┌────────────┴─────────────┐
                    │ Is Complex?              │
                    ├────────────┬─────────────┤
                    │ YES (→)    │ NO         │
                    │            │ (proceed   │
                    │            │  directly) │
                    ▼            └──→ CREATE  │
                                      LIST   │
┌─────────────────────────────────────────────────────────────────────────┐
│  2. QUESTION GENERATION (ListRefinementService)                         │
│  Model: gpt-4-turbo                                                       │
│                                                                           │
│  Input:                                                                   │
│  • List title: "Roadshow Organization Plan"                              │
│  • Category: "professional" (business context)                            │
│  • Domain: "event" (from complexity detection)                            │
│  • Items: []                                                              │
│                                                                           │
│  Prompt Logic:                                                            │
│  1. Check Category → PROFESSIONAL                                        │
│  2. Check Domain → event (roadshow)                                       │
│  3. Generate 3 matching questions from templates                          │
│                                                                           │
│  Questions Generated:                                                     │
│  Q1: "What is the main business objective of this ROADSHOW?"             │
│      (sales, lead generation, product launch, brand awareness)            │
│                                                                           │
│  Q2: "Which cities or regions will you visit, and how long?"             │
│      (location-specific planning)                                         │
│                                                                           │
│  Q3: "What activities or formats will you use at each stop?"             │
│      (demos, presentations, workshops, exhibitions, networking)           │
│                                                                           │
│  Output: JSON with 3 questions + context                                  │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  3. RENDER FORM (Pre-Creation Planning Template)                        │
│                                                                           │
│  UI Shows:                                                                │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ ❓ Before I create "Roadshow Organization Plan",                 │   │
│  │    I have a few questions                                        │   │
│  │                                                                  │   │
│  │ 1. What is the main business objective of this ROADSHOW?        │   │
│  │    [________________________________] (textarea)                │   │
│  │    💡 Understanding the primary objective helps tailor...       │   │
│  │                                                                  │   │
│  │ 2. Which cities or regions will you visit...?                   │   │
│  │    [________________________________] (textarea)                │   │
│  │    💡 Knowing the locations and duration helps plan...          │   │
│  │                                                                  │   │
│  │ 3. What activities or formats will you use...?                  │   │
│  │    [________________________________] (textarea)                │   │
│  │    💡 Identifying the types of activities allows...             │   │
│  │                                                                  │   │
│  │        [ Submit Answers ]  [ Cancel ]                           │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                           │
│  Stimulus Controller: pre_creation_planning_controller.js                │
│  • Validates all fields filled                                            │
│  • Joins answers with "\n---\n" separator                                 │
│  • Posts to /chats/:id/create_message                                     │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                    User fills form and clicks "Submit Answers"
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  4. PARAMETER EXTRACTION (ChatCompletionService)                        │
│  Model: gpt-5-nano                                                        │
│                                                                           │
│  Input:                                                                   │
│  • User answers (joined by "\n---\n")                                     │
│  • List context (title, category, items)                                  │
│                                                                           │
│  Prompt: "Extract planning parameters from these answers"                 │
│                                                                           │
│  Example User Answers:                                                    │
│  A1: "Sales and lead generation for our enterprise software"             │
│  A2: "4 cities: San Francisco, Chicago, Boston, New York. 4 weeks"       │
│  A3: "Product demos, sales workshops, executive networking"              │
│                                                                           │
│  Extracts:                                                                │
│  {                                                                        │
│    "duration": "4 weeks",                                                │
│    "budget": "not mentioned",                                             │
│    "locations": ["San Francisco", "Chicago", "Boston", "New York"],       │
│    "start_date": "June 2026",                                             │
│    "timeline": "4-week tour",                                             │
│    "team_size": "not mentioned",                                          │
│    "phases": ["Setup", "Tour", "Wrap-up"],                                │
│    "preferences": "Focus on enterprise decision-makers",                  │
│    "other_details": "Product demonstrations and networking focus"         │
│  }                                                                        │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  5. STRUCTURE ENRICHMENT (enrich_list_structure_with_planning)           │
│  No LLM call - Pure logic transformation                                 │
│                                                                           │
│  Input: Base params + Planning params                                     │
│                                                                           │
│  Enrichment Steps:                                                        │
│  1. Enhance description:                                                  │
│     "A plan to organize a roadshow starting in June this year."          │
│     ↓                                                                     │
│     "A plan to organize a roadshow starting in June this year. |         │
│      Duration: 4 weeks | Start: June 2026"                               │
│                                                                           │
│  2. Create nested lists by location:                                      │
│     Parent: "Roadshow Organization Plan"                                  │
│     ├─ San Francisco                                                      │
│     ├─ Chicago                                                            │
│     ├─ Boston                                                             │
│     └─ New York                                                           │
│                                                                           │
│  3. Distribute items to each location:                                    │
│     Each location inherits base items with location context:              │
│     • "Book venues" → "Book venues in San Francisco"                      │
│     • "Arrange transportation" → "Arrange transportation in SF"           │
│     • "Create marketing materials" → "Create marketing materials for SF" │
│                                                                           │
│  Output: Enriched structure ready for list creation                       │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  6. LIST CREATION (handle_list_creation)                                │
│  Model: gpt-4-turbo (optional, for item generation)                      │
│                                                                           │
│  Creates:                                                                 │
│  • Parent List: "Roadshow Organization Plan"                              │
│    ├─ Description: "...with planning context"                             │
│    ├─ Status: "draft" / "active"                                          │
│    └─ Nested Lists (4):                                                   │
│       ├─ San Francisco (contains 3+ location-specific items)              │
│       ├─ Chicago (contains 3+ location-specific items)                    │
│       ├─ Boston (contains 3+ location-specific items)                     │
│       └─ New York (contains 3+ location-specific items)                   │
│                                                                           │
│  Each item contains:                                                      │
│  • Title: "Book venues in San Francisco"                                  │
│  • Description: "Find and book suitable venues"                           │
│  • Location context: Inherited from parent location                       │
│                                                                           │
│  Metadata stored:                                                         │
│  • refinement_context: Original planning parameters                       │
│  • planning_domain: "event"                                               │
│  • category: "professional"                                               │
│  • skip_post_creation_refinement: true (we already refined!)              │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       FINAL LIST CREATED                                 │
│                                                                           │
│  🎉 Roadshow Organization Plan                                            │
│     A plan to organize a roadshow... | Duration: 4 weeks | Start: June   │
│                                                                           │
│     ├─ San Francisco                                                      │
│     │  ├─ Book venues in San Francisco                                    │
│     │  ├─ Arrange transportation in SF                                    │
│     │  └─ Create marketing materials for SF                               │
│     │                                                                     │
│     ├─ Chicago                                                            │
│     │  ├─ Book venues in Chicago                                          │
│     │  ├─ Arrange transportation in Chicago                               │
│     │  └─ Create marketing materials for Chicago                          │
│     │                                                                     │
│     ├─ Boston                                                             │
│     │  ├─ Book venues in Boston                                           │
│     │  ├─ Arrange transportation in Boston                                │
│     │  └─ Create marketing materials for Boston                           │
│     │                                                                     │
│     └─ New York                                                           │
│        ├─ Book venues in New York                                         │
│        ├─ Arrange transportation in New York                              │
│        └─ Create marketing materials for New York                         │
│                                                                           │
│  ✅ User can now edit and refine each location's tasks                    │
└─────────────────────────────────────────────────────────────────────────┘
```

## Prompt Models Summary

| Stage | Service | Model | Purpose | Cost |
|-------|---------|-------|---------|------|
| **1. Complexity** | ListComplexityDetectorService | gpt-5-nano | Light classification | $$$ |
| **2. Questions** | ListRefinementService | gpt-4-turbo | Domain-aware generation | $$$$$ |
| **3. Parameters** | ChatCompletionService | gpt-5-nano | Structured extraction | $$$ |
| **4. Enrichment** | - | None (logic) | Transform structure | Free |
| **5. Creation** | ChatResourceCreatorService | Optional gpt-4-turbo | Generate items | $$$$$ |

## Key LLM Prompts by Model

### GPT-5-Nano Prompts (Fast, Efficient)
1. **Complexity Detection:** Binary decision with reasoning
2. **Parameter Extraction:** JSON extraction from natural language

### GPT-4-Turbo Prompts (Smart, Detailed)
1. **Question Generation:** Context-aware question creation with domain specificity
2. **Item Enhancement:** Generate detailed descriptions for list items

---

## State Flow Diagram

```
Initial Request
       │
       ▼
Is Complex? ──NO──→ Create List Directly
       │
      YES
       │
       ▼
Generate 3 Questions
       │
       ▼
Store in chat.metadata["pending_pre_creation_planning"]
       │
       ▼
Render Form to User
       │
       ▼
User Submits Answers (new message)
       │
       ▼
Detect pending_pre_creation_planning flag
       │
       ▼
Extract Parameters from Answers
       │
       ▼
Enrich List Structure (nested lists by location/phase)
       │
       ▼
Create List with Enriched Structure
       │
       ▼
Clear pending_pre_creation_planning from metadata
       │
       ▼
Completed! ✅
```

---

## Error Handling

```
At any stage:
├─ JSON Parse Error → Log error, return empty/fallback
├─ LLM Failure → Log error, skip refinement, create basic list
├─ Parameter Extraction Fails → Use original parameters
├─ Enrichment Fails → Create flat list (no nesting)
└─ Final Fallback → Create simple list with original title/description
```

---

## Temperature & Configuration

| Service | Model | Temperature | Settings |
|---------|-------|-------------|----------|
| Complexity Detector | gpt-5-nano | 0.3 | Low temp = consistent results |
| Question Generator | gpt-4-turbo | Default (0.7) | Balanced creativity & coherence |
| Parameter Extraction | gpt-5-nano | Default (0.7) | Straightforward extraction |

Lower temperature (0.3) = More deterministic/consistent
Higher temperature (0.7) = More creative/varied
