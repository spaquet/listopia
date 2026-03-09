# Pre-Creation Planning Flow - Complete Explanation

## Current Flow When User Says: "I need to organize a roadshow starting in June"

### Step 1: User sends message
**File:** `app/controllers/messages_controller.rb` (or via chat API)
```
User Message: "I need to organize a roadshow starting in June"
         ↓
       Chat Model stores message
         ↓
   ChatCompletionService.call()
```

---

### Step 2: Intent Detection
**File:** `app/services/chat_completion_service.rb` (line 44-49)

```ruby
intent_result = AiIntentRouterService.new(
  user_message: @user_message,
  chat: @chat,
  user: @context.user,
  organization: @context.organization
).call
```

**File:** `app/services/ai_intent_router_service.rb`
- Uses LLM to detect intent
- Returns: `{ intent: "create_list" }`

---

### Step 3: Parameter Extraction
**File:** `app/services/chat_completion_service.rb` (line 58-61)

```ruby
if intent.in?(["create_list", "create_resource", "manage_resource"])
  parameter_check = check_parameters_for_intent(intent)
  return parameter_check if parameter_check
end
```

**File:** `app/services/chat_completion_service.rb` (line 143-171)
- Calls `ParameterExtractionService`

**File:** `app/services/parameter_extraction_service.rb`
- Uses LLM to extract: title, category, items, nested_lists
- Returns:
  ```ruby
  {
    resource_type: "list",
    parameters: {
      title: "Roadshow Organization Plan",
      category: "professional",
      items: ["Select target cities", "Book venues", ...],
      nested_lists: []
    },
    missing: [],
    needs_clarification: false
  }
  ```

---

### Step 4: Complexity Detection ⭐
**File:** `app/services/chat_completion_service.rb` (line 154-164)

```ruby
if intent == "create_list"
  parameters = data[:parameters] || {}

  # ⭐ NEW: Check if this is a complex request
  if needs_pre_creation_planning?(parameters)
    Rails.logger.info("Detected complex list request, routing to pre-creation planning")
    return handle_pre_creation_planning(parameters)
  else
    return handle_list_creation("list", parameters)
  end
end
```

**Method `needs_pre_creation_planning?`** (line 111-140)
Checks for:
- Multi-location patterns: "roadshow", "tour", "trip"
- Time-bound programs: "8-week", "monthly"
- Hierarchical structures: "phases", "stages"
- Large item counts: > 8 items
- Nested lists: > 2

**For roadshow:** ✅ MATCHES "roadshow" keyword → Returns `true`

---

### Step 5: Generate Pre-Creation Planning Questions ⭐⭐
**File:** `app/services/chat_completion_service.rb` (line 233-288)

Method: `handle_pre_creation_planning(parameters)`

```ruby
def handle_pre_creation_planning(parameters)
  title = "Roadshow Organization Plan"
  category = "professional"

  # ⭐ Reuse ListRefinementService to generate context-aware questions
  refinement = ListRefinementService.new(
    list_title: title,
    category: category,
    items: items,
    nested_sublists: nested_lists,
    context: @context
  )

  result = refinement.call
```

This is where the magic should happen! Let's trace into ListRefinementService...

---

### Step 6: Context-Aware Question Generation
**File:** `app/services/list_refinement_service.rb` (line 81-125)

#### 6a. Detect Planning Type
```ruby
def detect_planning_type
  title_lower = @list_title.downcase  # "roadshow organization plan"

  case title_lower
  when /roadshow|tour|event.*traveling|traveling.*event/
    :event_touring  # ✅ MATCHES!
  when /trip|vacation|travel|journey/
    :travel
  # ... other types ...
  else
    :general
  end
end
```

**For "Roadshow Organization Plan":** Returns `:event_touring`

#### 6b. Build Context-Specific Guidance
```ruby
def build_context_specific_guidance(planning_type)
  case planning_type
  when :event_touring
    <<~PROMPT
      SPECIAL GUIDANCE - ROADSHOW/TOURING EVENT:
      This is a multi-location event. Focus on questions that will help them organize across locations:
      - Which locations/cities are they visiting? (How many? In what regions?)
      - How many days/weeks? What's the timeline?
      - How many people attending at each location? Expected audience size?
      - Is there a team traveling with them or local partnerships?
      - What's the main purpose at each location? (Same format everywhere or customized?)

      EXAMPLE QUESTIONS FOR ROADSHOW:
      - "Which cities or regions will this roadshow visit?"
      - "How many stops do you plan, and what's the timeline between each location?"
      - "Are you expecting the same audience size at each location, and do you need to customize for each city?"
    PROMPT
```

#### 6c. Build Final Prompt
```ruby
def build_refinement_prompt
  planning_type = detect_planning_type  # :event_touring
  context_specific_guidance = build_context_specific_guidance(planning_type)

  base_prompt = <<~PROMPT
    You are an intelligent, thoughtful assistant helping someone organize and plan their activities.
    Your role is to ask 2-3 smart, specific clarifying questions that directly help them execute this plan better.
    Think like a professional organizer or project manager who understands their specific goal.

    IMPORTANT: Ask questions that are SPECIFIC to what they're actually trying to do, not generic questions.
    Generic questions are unhelpful. Smart questions show you understand their specific context.

    List Details:
    - Title: "Roadshow Organization Plan"
    - Category: professional
    - Planning Type Detected: event_touring
    - Main Items: Select target cities, Book venues, Create presentation materials, ...

    Core Principles:
    1. BE SPECIFIC: Ask questions that show you understand their EXACT type of planning
    2. BE THOUGHTFUL: Think about what they ACTUALLY need to know to execute this well
    3. AVOID GENERIC: Don't ask obvious questions like "Do you have a budget?" - everyone does
    4. FOCUS ON EXECUTION: Ask what will make them actually DO this successfully
    5. MAX 2-3 QUESTIONS: Keep it focused, not a survey
    6. DIRECT AND ACTIONABLE: Questions should lead to specific, useful information
    7. NATURAL LANGUAGE: Sound like a helpful colleague, not a form

    #{context_specific_guidance}  # ← This includes roadshow-specific guidance!
  PROMPT
```

#### 6d. Call LLM to Generate Questions
```ruby
def generate_refinement_questions
  llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4o-mini")

  system_prompt = build_refinement_prompt  # ← The prompt built above

  llm_chat.add_message(role: "system", content: system_prompt)
  llm_chat.add_message(role: "user", content: "Generate refinement questions for this list.")

  response = llm_chat.complete
```

**⚠️ ISSUE:** The LLM is supposed to see the roadshow-specific guidance, but it's returning generic project questions instead!

---

### Step 7: Store Planning State
**File:** `app/services/chat_completion_service.rb` (line 254-262)

```ruby
@chat.metadata["pending_pre_creation_planning"] = {
  extracted_params: parameters,
  questions_asked: questions.map { |q| q["question"] },
  refinement_context: result.data[:refinement_context],
  intent: "create_list"
}
@chat.save
```

---

### Step 8: User Answers Planning Questions
**User:** "San Francisco, Austin, Boston. 2 days each. 50-100 attendees."

---

### Step 9: Process Planning Answers
**File:** `app/services/chat_completion_service.rb` (line 269-313)

Method: `handle_pre_creation_planning_response`

```ruby
def handle_pre_creation_planning_response
  planning_data = @chat.metadata["pending_pre_creation_planning"]

  # Extract parameters from user's answers
  planning_params = extract_planning_parameters_from_answers(
    user_answers: "San Francisco, Austin, Boston. 2 days each. 50-100 attendees.",
    list_title: "Roadshow Organization Plan",
    category: "professional",
    initial_items: [...]
  )

  # Enrich list structure
  enriched_params = enrich_list_structure_with_planning(
    base_params: extracted_params,
    planning_params: planning_params
  )
```

---

### Step 10: Enrich List Structure
**File:** `app/services/chat_completion_service.rb` (line 685-738)

Method: `enrich_list_structure_with_planning`

```ruby
def enrich_list_structure_with_planning(base_params:, planning_params:)
  enriched = base_params.dup

  # If locations mentioned, create nested lists
  if planning_params["locations"].present?  # ["San Francisco", "Austin", "Boston"]
    enriched["nested_lists"] = planning_params["locations"].map do |location|
      {
        "title" => location,
        "description" => "Tasks and activities for #{location}",
        "items" => (enriched["items"] || []).map do |item|
          { "title" => item, "description" => "In #{location}" }
        end
      }
    end
    enriched["items"] = []  # Clear parent items
  end

  enriched
end
```

**Result:**
```ruby
{
  title: "Roadshow Organization Plan",
  category: "professional",
  nested_lists: [
    {
      title: "San Francisco",
      description: "Tasks and activities for San Francisco",
      items: [
        { title: "Select target cities", description: "In San Francisco" },
        { title: "Book venues", description: "In San Francisco" },
        ...
      ]
    },
    {
      title: "Austin",
      description: "Tasks and activities for Austin",
      items: [...]
    },
    {
      title: "Boston",
      description: "Tasks and activities for Boston",
      items: [...]
    }
  ]
}
```

---

### Step 11: Create Enriched List
**File:** `app/services/chat_completion_service.rb` (line 298)

```ruby
creation_result = handle_list_creation("list", enriched_params)
```

**File:** `app/services/chat_resource_creator_service.rb`
- Creates the List with nested structure
- Creates ListItems for each location-specific task

---

### Step 12: Skip Post-Creation Refinement
**File:** `app/services/chat_completion_service.rb` (line 544-549)

```ruby
def trigger_list_refinement(list:, list_title:, category:, items:, message:, nested_sublists: [])
  # Skip post-creation refinement if we already did pre-creation planning
  if @chat.metadata&.dig("skip_post_creation_refinement")
    Rails.logger.info("Skipping post-creation refinement (pre-creation planning was completed)")
    return success(data: { needs_refinement: false, message: message })
  end

  # ... normal refinement questions would go here ...
end
```

---

## Files Summary

| File | Lines | Purpose |
|------|-------|---------|
| `app/services/chat_completion_service.rb` | 109-140 | `needs_pre_creation_planning?` - Detect if complex |
| `app/services/chat_completion_service.rb` | 233-288 | `handle_pre_creation_planning` - Ask planning questions |
| `app/services/chat_completion_service.rb` | 269-313 | `handle_pre_creation_planning_response` - Process answers |
| `app/services/chat_completion_service.rb` | 632-683 | `extract_planning_parameters_from_answers` - Parse user's answers |
| `app/services/chat_completion_service.rb` | 685-738 | `enrich_list_structure_with_planning` - Create nested lists |
| `app/services/list_refinement_service.rb` | 81-125 | `build_refinement_prompt` - Build question prompt |
| `app/services/list_refinement_service.rb` | 128-153 | `detect_planning_type` - Detect roadshow/travel/etc |
| `app/services/list_refinement_service.rb` | 156-256 | `build_context_specific_guidance` - Type-specific guidance |
| `app/services/parameter_extraction_service.rb` | 28-127 | Extract title, category, items from user input |
| `app/services/ai_intent_router_service.rb` | - | Detect create_list intent |

---

## The Problem

The flow IS correct and the context-specific guidance IS being passed to the LLM. However, the LLM is **not following the guidance** and instead reverting to generic project management questions.

**Why?**
1. The LLM might be ignoring the specific guidance examples
2. The prompt might not have enough emphasis on using the examples
3. The system prompt formatting might be getting lost when passed to the LLM

**Solution Options:**
1. Make the prompt MORE forceful about using the examples
2. Ask the LLM to DIRECTLY USE the provided examples
3. Separate the question generation into: "Here are examples, now generate similar ones"
4. Add a secondary validation step that checks if questions match the planning type
