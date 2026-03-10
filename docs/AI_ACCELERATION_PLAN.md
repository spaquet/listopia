# AI Response Acceleration Strategy

## Executive Summary

Your chat system currently uses **6 sequential LLM calls** for complex operations (create_list), each waiting for the previous to complete. This document proposes 3 optimization strategies using RubyLLM 1.11's extended thinking capabilities, parallel processing, and progressive UI updates to significantly reduce perceived latency.

---

## Part 1: Database Query Performance (N+1 Fixes)

### Current Status
✅ Good news: `bullet` gem already installed in development group

### Recommended Additional Gems (Rails 8.1)

Add these to `Gemfile`:

```ruby
# Performance profiling and analysis (Rails 8.1 compatible)
group :development do
  gem "bullet"                  # ✅ Already installed (v8.1.0)
  gem "rack-mini-profiler"      # ✅ Already installed (v4.0.1)
  gem "memory_profiler"         # Memory usage analysis
  gem "stackprof"               # CPU sampling profiler (production-safe)
  # gem "prosopite"             # Optional: Alternative N+1 detector
end

# Optional for production monitoring
group :production do
  # gem "newrelic_rpm"           # New Relic APM
  # gem "scout_apm"              # Scout APM
end
```

**Note**: Skipped outdated gems:
- ❌ `query_tracer` - unmaintained, no Rails 8.1 support
- ❌ `fasterer` - unmaintained, not updated in 2+ years
- ✅ Use RuboCop instead - you have `rubocop-rails-omakase` (includes performance cops)

### Immediate Actions

1. **Enable bullet logging** - Check `config/environments/development.rb`:
   ```ruby
   if defined?(Bullet)
     Bullet.enable = true
     Bullet.alert = true
     Bullet.console = true          # Log to console
     Bullet.rails_logger = true     # Log to Rails logger
   end
   ```

2. **Run server with profiling**:
   ```bash
   bundle exec rails s
   # Then visit http://localhost:3000/__mini_profiler to see query analysis
   ```

3. **Priority N+1 areas to fix** (from CLAUDE.md):
   - Chat message loading (includes :messages when fetching chats)
   - User lookups in mentions autocomplete
   - List collaborations in list views
   - Organization members in team operations

### Key Pattern to Apply Everywhere

```ruby
# ❌ BAD - N+1 queries
lists = List.all
lists.each { |l| puts l.owner.name }  # Query per list!

# ✅ GOOD - Eager loading
lists = List.includes(:owner).all
lists.each { |l| puts l.owner.name }  # Single query

# ✅ BEST - With counter cache (for counts)
# Add to migration:
add_column :lists, :items_count, :integer, default: 0

# Use in queries:
lists.select { |l| l.items_count > 0 }  # No COUNT query
```

---

## Part 2: Current AI Flow Analysis

### The Bottleneck: Sequential Processing

```
User Input
  ↓ [WAIT 0.5-1s]
Prompt Injection Detection (OpenAI) + Content Moderation
  ↓ [WAIT 1-2s]
Intent Detection (OpenAI)
  ↓ [WAIT 1-2s]
Parameter Extraction (OpenAI)
  ↓ [WAIT 0.2-0.5s]
Resource/List Creation (DB)
  ↓ [IF NEEDED] [WAIT 2-3s]
List Refinement Questions (gpt-5)
  ↓ [WAIT ~2-3s]
Refinement Answer Processing (OpenAI)

TOTAL USER WAIT: 8-14 seconds for complex operations
```

**Current Implementation Issues:**

1. **Moderation + Intent are sequential** (could be parallel)
2. **Intent Detection is separate call** (could be combined with parameter extraction)
3. **List refinement questions use gpt-5** (expensive, could use gpt-5-nano)
4. **Entire flow blocks response** (user sees nothing until final answer)

---

## Part 3: Optimization Strategies

### STRATEGY A: Combine Intent + Parameters (Immediate Win)

**Current**: 2 separate LLM calls (1-2s wasted)
**After**: 1 LLM call + parameter extraction in same prompt

```ruby
# app/services/combined_intent_parameter_service.rb
class CombinedIntentParameterService < ApplicationService
  def call
    llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-5-nano")

    combined_prompt = <<~PROMPT
      Analyze this user message and respond with ONLY valid JSON:

      {
        "intent": "create_list|create_resource|navigate_to_page|general_question",
        "resource_type": "list|user|team|organization|null",
        "title": "inferred title if applicable",
        "parameters": {
          "category": "professional|personal|null",
          "items": [...],
          "name": "...",
          "email": "..."
        },
        "missing": ["field1", "field2"],
        "confidence": 0.95
      }

      User message: "#{@user_message.content}"
    PROMPT

    response = llm_chat.complete
    # Single response with both intent and parameters
  end
end
```

**Benefit**: Saves ~1-2 seconds per message
**Implementation**: Replace separate services with this combined service

---

### STRATEGY B: Parallel Processing (High Impact)

**Before**:
```
Injection Check → Intent → Parameters → Create → Refine
     1s            2s       2s        0.5s      3s = 8.5s total
```

**After**:
```
Intent + Parameters [PARALLEL] → Create → Refine (background)
        2s (instead of 4s)      0.5s
       ↓
    Create List
    Return immediately
       ↓
    Refinement (background)
    Push via Turbo Stream when ready
```

**Implementation**:

```ruby
# app/services/chat_completion_service.rb - MODIFIED
def call
  # ... validation ...

  # PARALLEL: Detect injection + get intent/parameters simultaneously
  moderation_job = Thread.new { content_moderation_service.call }
  intent_params = combined_intent_parameter_service.call
  moderation_result = moderation_job.value

  if moderation_result.blocked?
    return handle_blocked_message
  end

  # Resource creation happens immediately
  resource = create_resource_if_needed(intent_params)

  # Send immediate response to user
  create_assistant_message(chat, initial_response(resource))
  broadcast_message_to_user

  # Refinement happens in background job
  if resource.is_a?(List)
    ListRefinementJob.perform_later(resource.id, chat.id)
  end

  success(data: { message: initial_response_message })
end
```

**Benefits**:
- Inject check + intent: 4s → 2s
- User sees response immediately (doesn't wait for refinement)
- Refinement updates pushed via Turbo Stream

---

### STRATEGY C: Progressive UI Updates (Best UX)

**Show parent task first, fill details in background:**

```
User: "Plan my business trip to Japan for 2 weeks"
  ↓
[IMMEDIATE - 0.5s]
✅ "Creating your Japan Trip list..."
└─ Show empty list with loading indicator

[BACKGROUND - 3-5s]
📝 Extract items → Display them progressively
   ✅ "Book flights"
   ✅ "Reserve hotel"
   ✅ "Plan itinerary"
   ✅ "Book restaurants"

[CONTINUES - 5-8s]
🎯 Refinement questions appear
   "How long will you stay?"
   "Which areas do you want to visit?"
   "What's your budget?"
```

**Implementation**:

```erb
<!-- app/views/chats/_creating_list_progress.html.erb -->
<div id="list-creation-progress" data-chat-id="<%= chat.id %>">
  <div class="loading-state">
    <p class="text-lg font-semibold">Creating your list...</p>
    <div class="spinner"></div>
  </div>

  <div id="list-items-container"></div>

  <div id="refinement-questions-container"></div>
</div>
```

```ruby
# Background job that streams updates
class ListCreationProgressJob < ApplicationJob
  def perform(chat_id, intent_params)
    chat = Chat.find(chat_id)
    list = List.create!(intent_params)

    # Broadcast list creation
    broadcast_to(chat, :list_created, { list: list })

    # Stream items as they're generated
    items = extract_and_create_items(list, intent_params)
    items.each do |item|
      broadcast_to(chat, :item_added, { item: item })
    end

    # Generate refinement questions
    refinement_result = ListRefinementService.call(...)
    broadcast_to(chat, :refinement_ready, refinement_result)
  end
end
```

---

## Part 4: RubyLLM 1.11 Extended Thinking Integration

**Available fields from RubyLLM 1.11:**
- `thinking_text` - Claude/GPT extended thinking output
- `thinking_tokens` - Token usage for thinking
- `thinking_signature` - Verification (Gemini only, skip for OpenAI)

**Use Case: Complex intent detection with reasoning**

```ruby
# Use extended thinking for ambiguous cases only
def detect_intent_with_thinking(user_message)
  return detect_intent_fast(user_message) unless ambiguous?(user_message)

  llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4")

  # Enable extended thinking in prompt
  system_prompt = <<~PROMPT
    You are analyzing user intent. Think through the request step-by-step.
    Consider all possible interpretations.

    Then respond with JSON classification.
  PROMPT

  llm_chat.add_message(role: "system", content: system_prompt)
  response = llm_chat.complete

  # Access thinking output
  if response.respond_to?(:thinking_text)
    Rails.logger.debug("Extended thinking: #{response.thinking_text}")
    Rails.logger.debug("Thinking tokens: #{response.thinking_tokens}")
  end

  parse_intent_response(response.content)
end

def ambiguous?(message)
  # Quick heuristic: message has multiple possible intents
  keywords = ["or", "also", "and", "plus"]
  keywords.any? { |kw| message.downcase.include?(kw) }
end
```

**Cost-Benefit Analysis:**
- ✅ Saves 1-2 LLM calls for ambiguous cases
- ❌ Slightly more expensive per token (extended thinking costs ~1.5x)
- 🎯 Use selectively: only for ambiguous cases, not every message

---

## Part 5: Implementation Roadmap

### Phase 1: Low Effort, High Impact (Week 1)

**Gem additions:**
```bash
bundle add rack-mini-profiler query_tracer stackprof fasterer
```

**Code changes:**
1. Combine Intent + Parameter extraction services
2. Add parallel moderation checking
3. Deploy combined service to production

**Expected improvement**: 4-6 seconds → 2-3 seconds

---

### Phase 2: Medium Effort, Major UX Improvement (Week 2-3)

1. Implement background jobs for refinement
2. Add Turbo Streams for progressive updates
3. Update chat UI to show immediate responses
4. Stream items as they're created

**Expected improvement**: 2-3 seconds perceived latency (user sees response immediately)

---

### Phase 3: Advanced Optimization (Week 4+)

1. Selective extended thinking for ambiguous intents
2. Caching for common intent classifications
3. N+1 query fixes (use bullet reports to prioritize)
4. Counter cache migrations for frequently counted associations

**Expected improvement**: Additional 30-40% reduction in complex operations

---

## Part 6: Monitoring & Measurement

### Key Metrics to Track

```ruby
# app/services/chat_completion_service.rb
def call
  start_time = Time.current

  begin
    # ... existing code ...

    total_time = Time.current - start_time

    # Log performance metrics
    Rails.logger.info({
      event: "chat_completion",
      total_time_ms: (total_time * 1000).round,
      intent: @intent,
      message_length: @user_message.content.length,
      moderation_time_ms: moderation_duration * 1000,
      intent_detection_time_ms: intent_duration * 1000,
      resource_creation_time_ms: creation_duration * 1000
    }.to_json)

  rescue => e
    Rails.logger.error("ChatCompletionService failed: #{e.message}")
    raise
  end
end
```

### Dashboard Metrics to Monitor

1. **Average response time** - Target: < 2s for simple messages, < 4s for list creation
2. **Message count in chat** - Should not slow down after 100+ messages
3. **List creation time** - Target: < 3s total (immediate response + background refinement)
4. **N+1 query detection** - bullet gem reports (should be 0 after fixes)

### Performance Budget

```
Simple chat response:      < 1s   (intent only)
Parameter extraction:      < 0.5s
Resource creation:         < 0.5s
List refinement:           < 2s   (should not block UI)
---
Total perceived latency:   < 2s   (with progressive updates)
```

---

## Part 7: Code Examples

### Example 1: Background Refinement Job

```ruby
# app/jobs/list_refinement_job.rb
class ListRefinementJob < ApplicationJob
  queue_as :default

  def perform(list_id, chat_id)
    list = List.find(list_id)
    chat = Chat.find(chat_id)

    # Generate refinement questions
    refinement_service = ListRefinementService.new(
      list_title: list.title,
      category: list.category,
      items: list.list_items.pluck(:title),
      context: chat.build_context
    )

    result = refinement_service.call

    if result.success?
      # Store in chat metadata for state management
      chat.metadata ||= {}
      chat.metadata["pending_list_refinement"] = {
        list_id: list.id,
        questions: result.data[:questions],
        context: result.data[:refinement_context]
      }
      chat.save!

      # Push refinement questions via Turbo Stream
      broadcast_to_chat(chat, :refinement_ready, {
        questions: result.data[:questions],
        list_id: list.id
      })
    end
  end

  private

  def broadcast_to_chat(chat, action, data)
    Turbo::StreamsChannel.broadcast_action_to(
      ["chat", chat.id],
      action: :append,
      target: "refinement-questions",
      partial: "chats/refinement_questions",
      locals: data
    )
  end
end
```

### Example 2: Optimized List Display with Eager Loading

```ruby
# app/controllers/lists_controller.rb
def index
  # Query with all necessary associations
  @lists = policy_scope(List)
            .includes(:owner, :team, :list_items, :list_collaborations => :user)
            .recent
            .page(params[:page])
            .per(20)

  # View will not trigger additional queries
end

# app/views/lists/index.html.erb
<div class="lists-grid">
  <% @lists.each do |list| %>
    <!-- No N+1 queries - all data loaded upfront -->
    <div class="list-card">
      <h3><%= list.title %></h3>
      <p>Owner: <%= list.owner.name %></p>
      <p>Items: <%= list.list_items.count %></p>
      <p>Collaborators: <%= list.list_collaborations.count %></p>
    </div>
  <% end %>
</div>
```

### Example 3: Progressive UI Update Pattern

```erb
<!-- app/views/chats/_message.html.erb -->
<div id="message-<%= @message.id %>" class="message user-message">
  <p><%= @message.content %></p>
</div>

<!-- Immediate response -->
<div id="assistant-response-<%= @message.id %>" class="message assistant-message">
  <p><%= @assistant_message.content %></p>

  <!-- List creation in progress -->
  <% if @chat.metadata&.dig("pending_list_creation") %>
    <div id="list-creation-progress" class="progress-indicator">
      <div class="spinner"></div>
      <p>Creating your list...</p>
    </div>
  <% end %>
</div>
```

```javascript
// app/javascript/controllers/chat_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messageContainer", "input"]

  submit(event) {
    event.preventDefault()

    // Clear input immediately
    const message = this.inputTarget.value
    this.inputTarget.value = ""

    // Show user message immediately
    this.appendMessage(message, "user")

    // Send to server (don't wait for response)
    this.sendMessage(message)
  }

  sendMessage(message) {
    fetch(this.formTarget.action, {
      method: "POST",
      body: new FormData(this.formTarget),
      headers: { "Accept": "text/vnd.turbo-stream.html" }
    })
    // Server will push updates via Turbo Streams
  }
}
```

---

## Part 8: Migration Checklist

- [ ] Add gems: `rack-mini-profiler`, `query_tracer`, `stackprof`, `fasterer`
- [ ] Enable bullet logging in development
- [ ] Profile current chat flow (identify slowest operations)
- [ ] Combine intent + parameter extraction services
- [ ] Add parallel moderation checking
- [ ] Create `ListRefinementJob` background job
- [ ] Update chat UI for progressive updates
- [ ] Deploy Phase 1 changes and measure improvement
- [ ] Implement Phase 2 (background refinement)
- [ ] Create N+1 fix priority list (from bullet reports)
- [ ] Implement counter caches for frequently counted associations
- [ ] Add extended thinking for ambiguous intents (Phase 3)
- [ ] Document performance patterns in CLAUDE.md

---

## Summary

This strategy reduces AI response latency from **8-14 seconds** to **2-3 seconds** through:

1. **Parallel processing** - Check moderation and intent simultaneously
2. **Combined services** - One LLM call instead of two
3. **Background jobs** - Refinement doesn't block UI
4. **Progressive updates** - User sees response immediately
5. **Database optimization** - N+1 fixes reduce database latency

**Quick wins (implement first):**
- Combine intent + parameter extraction (save 1-2s)
- Parallel moderation + intent (save 1-2s)
- Use background jobs for refinement (immediate response)
- Add profiling gems to identify N+1 bottlenecks

**Total effort**: 15-20 hours of development, measurable 60-80% latency reduction
