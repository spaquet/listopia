# Item Generation Service

Intelligent, context-aware item generation for Listopia's pre-creation planning system.

## Overview

`ItemGenerationService` generates appropriate list items based on user context. Instead of hardcoded logic for specific use cases (locations, phases, etc.), it uses a single generic approach powered by Claude's reasoning capabilities (gpt-5.4-2026-03-05).

**Key principle**: The LLM analyzes the planning context to intelligently determine what items are needed, rather than having hardcoded rules for each domain.

## When It's Used

ItemGenerationService is called during the **pre-creation planning phase** when a user's request is detected as "complex" and requires clarification:

```
User: "Help me plan our roadshow for Listopia"
  ↓
System: "This is complex - I need more details"
  ↓
System: Asks 3 clarifying questions
  ↓
User: Answers with locations (NY, LA, Chicago, SF, Seattle), budget ($500k), dates (June-Sept)
  ↓
ItemGenerationService: Called for each sublist (each city)
  ↓
Sublists created with appropriate items for each location
```

## Architecture

### Service Location
`app/services/item_generation_service.rb`

### Key Dependencies
- **RubyLLM 1.11+** - LLM integration
- **gpt-5.4-2026-03-05** - Reasoning model for sophisticated item generation
- **ApplicationService** - Base service class

### Call Flow

```ruby
# In ChatCompletionService#enrich_list_structure_with_planning
result = ItemGenerationService.new(
  list_title: "roadshow for Listopia",
  description: "Budget: $500k | Timeline: June-Sept",
  category: "professional",
  planning_context: {
    locations: ["New York", "Los Angeles", ...],
    budget: "$500000",
    timeline: "June 2026 to September 2026",
    ...
  },
  sublist_title: "New York"  # Optional
).call

# Result is a service Result object
if result.success?
  items = result.data  # Array of item hashes with title, description, type, priority
end
```

## Usage

### Basic Usage (for a sublist)

```ruby
ItemGenerationService.new(
  list_title: "Plan US Roadshow",
  description: "Budget: $500,000 | Start: June 2026",
  category: "professional",
  planning_context: {
    locations: ["New York", "Los Angeles", "Chicago"],
    budget: "$500,000",
    timeline: "June - September 2026"
  },
  sublist_title: "New York"
).call
```

### Return Value

Success returns an array of item hashes:

```ruby
[
  {
    title: "Confirm venue booking at Times Square location",
    description: "Contact venue to confirm date availability and negotiate terms. Ensure capacity meets expected attendance of 200+ people.",
    type: "task",
    priority: "high"
  },
  {
    title: "Arrange local transportation logistics",
    description: "Book buses for airport pickups and venue transfers. Confirm with local dispatcher for day-of coordination.",
    type: "task",
    priority: "high"
  },
  ...
]
```

### Error Handling

Gracefully returns empty array on any error:

```ruby
result = ItemGenerationService.new(...).call

if result.success?
  items = result.data  # Array, might be empty on error
else
  # Service handles errors internally, returns success with []
  items = []
end
```

## Design Philosophy

### Why Generic Service?

The old approach had three hardcoded methods:
- `generate_location_specific_items` - only for locations
- `generate_phase_specific_items` - only for phases
- `generate_context_aware_items` - generic fallback, still limited

**Problems:**
- Not scalable - needed a new method for each subdivision type
- Bug-prone - each method had similar logic with subtle differences
- Hard to maintain - three places to update when fixing issues

### New Approach

**Single intelligent service** that works for:
- ✅ Locations (roadshow planning)
- ✅ Phases (project planning, phased rollouts)
- ✅ Weeks/Chapters (learning paths, course planning)
- ✅ Sprints (agile planning)
- ✅ Sections (any custom subdivision)
- ✅ Unknown future subdivision types

The LLM automatically determines what items are appropriate based on context.

## Prompt Strategy

The service uses a sophisticated prompt that:

1. **Identifies the domain** - Event, travel, learning, project, business, etc.
2. **Analyzes the context** - Locations, budget, timeline, category
3. **Generates specific items** - Not generic duplicates, but items unique to each subdivision
4. **Considers constraints** - Budget, timeline, team size, preferences

### Prompt Structure

```
Analyze the planning request and generate 5-8 specific, actionable items.

Planning Context:
- List: "roadshow for Listopia"
- Category: professional
- Focus: Generate items SPECIFICALLY for: New York
- Budget: $500,000
- Timeline: June 2026 - September 2026
- Locations: [list of all cities]

Your Task:
1. Understand the DOMAIN (event, travel, learning, project, business, etc.)
2. Generate items that are SPECIFIC and APPROPRIATE to New York
   - NOT generic duplicates of other locations
   - Consider local logistics, vendors, regulations, partnerships
3. Avoid generic placeholders
4. Return JSON array with title, description, type, priority
```

## Model Selection

### Why gpt-5.4-2026-03-05?

- **Extended Thinking**: Sophisticated reasoning about what items are needed
- **Context Understanding**: Better analysis of planning domain and requirements
- **Quality**: More specific, actionable items vs generic suggestions
- **Reliability**: Fewer parsing errors and invalid responses

### Trade-offs

- Slightly slower than gpt-5-nano (~2-3s vs ~1s)
- Cost is negligible per call
- Result quality is significantly higher
- Worth the latency for user-facing feature

## Implementation Details

### Item Format

Items must have these fields:

```ruby
{
  title: String,        # 1-10 words, action-oriented
  description: String,  # 1-3 sentences, specific details
  type: String,        # "task", "milestone", "reminder", "note"
  priority: String     # "high", "medium", "low"
}
```

### Formatting

The service converts various input formats to consistent hash format:

```ruby
# Accepts strings...
"Complete venue reservation"
# ↓ converts to ↓
{ title: "Complete venue reservation", description: "", type: "task", priority: "medium" }

# Accepts hashes...
{ "title" => "...", "description" => "..." }
# ↓ converts to ↓
{ title: "...", description: "...", type: "task", priority: "medium" }
```

### Error Handling

The service catches and handles:
- LLM API failures → Returns empty array
- JSON parsing errors → Returns empty array
- Missing fields → Applies defaults (type: "task", priority: "medium")
- Nil inputs → Converted to empty string/array

## Integration Points

### Called From
`ChatCompletionService#enrich_list_structure_with_planning` when creating nested lists for:
- `:locations` - multi-city events, roadshows
- `:phases` - phased projects, rollouts
- `:other` - any custom subdivision

### Feeds Into
`ListCreationService#create_list_with_structure` which uses generated items to populate sublists.

## Testing

### Unit Testing Example

```ruby
describe ItemGenerationService do
  let(:service) do
    described_class.new(
      list_title: "Plan US Roadshow",
      description: "Budget: $500k",
      category: "professional",
      planning_context: { locations: ["NYC"], budget: "$500k" },
      sublist_title: "New York"
    )
  end

  it "returns success with items" do
    result = service.call
    expect(result.success?).to be true
    expect(result.data).to be_an Array
    expect(result.data.first.keys).to include(:title, :description, :type, :priority)
  end

  it "gracefully handles LLM errors" do
    allow_any_instance_of(RubyLLM::Chat).to receive(:complete).and_raise("API error")
    result = service.call
    expect(result.success?).to be true
    expect(result.data).to eq([])
  end
end
```

### Integration Testing Example

```ruby
it "creates roadshow sublists with location-specific items" do
  # Trigger pre-creation planning flow
  chat = Chat.create!(user: user, organization: org)
  message = Message.create_user(chat: chat, user: user, content: "plan roadshow")

  # Answer refinement questions with locations
  answers = "Locations: NYC, LA, Chicago\nBudget: $500k\nDates: June-Sept"
  Message.create_user(chat: chat, user: user, content: answers)

  # Process and create list
  service = ChatCompletionService.new(chat, message)
  result = service.call

  # Verify sublists have items
  expect(List.last.sub_lists.count).to eq(3)
  expect(List.last.sub_lists.first.list_items.count).to be > 0
end
```

## Performance Considerations

### Latency
- Per-sublist: ~2-3 seconds (one LLM call per subdivision)
- Parallel would require async job queueing (future optimization)
- Current: Sequential (acceptable for 3-5 sublists)

### Cost
- ~$0.01 per call at current rates
- Negligible for typical use (1-10 sublists per list)
- Could optimize with caching if needed

### Optimization Ideas

1. **Parallel Generation** - Use background jobs for each sublist
2. **Prompt Caching** - Cache system prompt between calls
3. **Smart Aggregation** - Generate items for all sublists in one LLM call
4. **Template Library** - Pre-generate common item patterns by domain

## Common Issues & Solutions

### Empty Items Array
- **Cause**: JSON parsing failed silently
- **Solution**: Check logs for "JSON parse error"
- **Prevention**: Service returns empty array gracefully, UI shows empty sublist

### Generic Items Generated
- **Cause**: LLM ignored sublist_title context
- **Solution**: Verify prompt includes sublist_title and planning_context
- **Prevention**: Update prompt to emphasize specificity

### Slow Generation
- **Cause**: gpt-5.4 reasoning is slower than gpt-5-nano
- **Solution**: This is expected trade-off for quality
- **Optimization**: Consider async generation in background jobs

## Future Enhancements

1. **Batch Processing** - Generate items for multiple sublists in one call
2. **Template Selection** - Choose prompt template based on planning_domain
3. **User Preferences** - Customize item generation style per user
4. **Multi-language** - Support item generation in other languages
5. **Item Prioritization** - Automatically set priority based on domain rules
6. **Dependency Tracking** - Identify item dependencies within sublists

## Related Services

- **ListRefinementService** - Generates clarifying questions before item generation
- **CombinedIntentComplexityService** - Detects if list is "complex" and needs refinement
- **ListCreationService** - Creates lists and sublists with generated items
- **ChatCompletionService** - Orchestrates the entire flow

## Files

- Implementation: `app/services/item_generation_service.rb`
- Usage: `app/services/chat_completion_service.rb` (line 1018-1070)
- Tests: `spec/services/item_generation_service_spec.rb` (when created)
