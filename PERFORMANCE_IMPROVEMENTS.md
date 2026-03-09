# Chat Performance Improvements Guide

Complete guide for analyzing and optimizing Listopia's AI chat system performance.

**Last Updated:** January 2026
**Status:** In Progress - Using gpt-5-nano, form bug identified, profiling tools configured

---

## Current Status

### ✅ What's Been Done
- Changed `AiIntentRouterService` to use `gpt-5-nano` (from `gpt-4o-mini`)
- Changed `ParameterExtractionService` to use `gpt-5-nano` (from `gpt-4o-mini`)
- Changed `ListRefinementService` to use `gpt-5` (from `gpt-4-turbo`)
- Improved parameter extraction prompt to emphasize title requirement (reduces retries)
- Confirmed `gpt-5-nano` and `gpt-5` models exist and work
- Identified 2 performance bottlenecks:
  - **Step 1:** Pre-creation planning questions generation (if needed)
  - **Step 2:** List & sublist creation

### 🔴 Known Issue
**Form Persistence Bug:** Pre-creation planning form remains on screen after submission instead of being removed

### 🟡 Not Doing (Due to Credits)
- ~~Switch `AiIntentRouterService` to Claude 3.5 Haiku~~ (no Anthropic credits)
- ~~Migrate to Anthropic API~~ (using OpenAI exclusive with gpt-5 models)

### 🟢 Next: Performance Analysis & Optimization
Scientifically identify bottleneck using Stackprof, then apply targeted optimizations

---

## The Problem: Two Slow Steps

When a user creates a complex list via chat:

```
STEP 1: Pre-Creation Planning Questions (if complexity detected)
├─ ListComplexityDetectorService checks if request is complex (LLM call)
└─ ListRefinementService generates 3 clarifying questions (LLM call + gpt-5)
Result: User sees form asking for clarification
Duration: ~2-3 seconds

STEP 2: List & Sublist Creation (after user answers questions)
├─ extract_planning_parameters_from_answers (LLM call)
├─ enrich_list_structure_with_planning (multiple LLM calls per location/phase)
│  ├─ generate_location_specific_items (LLM call × N locations)
│  ├─ generate_phase_specific_items (LLM call × N phases)
│  └─ generate_context_aware_items (LLM call × N sections)
└─ handle_list_creation (database inserts)
Result: List created with all items and sublists
Duration: ~5-10 seconds
```

**Total time:** 7-13 seconds (slow, especially Step 2)

---

## Performance Analysis Strategy

### Why Manual Logging is Wrong
- Adds overhead to production code
- Hard to interpret timing
- Doesn't show call stacks or memory usage
- Not how professionals do it

### The Right Way: Profiling Tools

We use **Stackprof** (CPU profiler) to scientifically identify bottlenecks:
- Shows which methods consume most time
- Displays call stacks visually
- Zero overhead
- Industry standard

---

## Step 1: Install Stackprof

```bash
# Add to Gemfile (development group)
echo 'gem "stackprof", require: false' >> Gemfile

# Install
bundle install
```

---

## Step 2: Create Profiling Task

**Create file:** `lib/tasks/profile_chat.rake`

```ruby
namespace :profile do
  desc "Profile pre-creation planning chat flow"
  task chat: :environment do
    require 'stackprof'

    # Setup test data
    user = User.first || (puts "Error: Need at least one user" and exit 1)
    org = user.organizations.first || (puts "Error: User needs an organization" and exit 1)
    chat = Chat.create!(user: user, organization: org)
    context = ChatContext.new(chat: chat, user: user, organization: org, location: :dashboard)

    # Message that triggers pre-creation planning
    message_content = "Plan a roadshow across 3 US cities: New York, Chicago, and San Francisco. " \
                     "Focus on sales and marketing activities at each location."
    user_message = Message.create_user(chat: chat, user: user, content: message_content)

    puts "\n🚀 Starting CPU profile..."
    puts "   This will profile the entire chat completion flow"
    puts "   Duration: ~30-60 seconds\n\n"

    # Profile the service
    StackProf.run(mode: :cpu, out: "tmp/stackprof-chat.dump", interval: 1000) do
      ChatCompletionService.new(chat, user_message, context).call
    end

    puts "\n✅ Profiling complete!\n\n"
    puts "=" * 80
    puts "📊 VIEW RESULTS:"
    puts "=" * 80
    puts "\nText summary:"
    puts "  stackprof tmp/stackprof-chat.dump"
    puts "\nInteractive HTML graph (recommended):"
    puts "  stackprof --d3 tmp/stackprof-chat.dump > tmp/profile.html && open tmp/profile.html"
    puts "\n" + "=" * 80
  end
end
```

---

## Step 3: Run the Profiler

```bash
bundle exec rake profile:chat
```

**Output:**
```
🚀 Starting CPU profile...
   This will profile the entire chat completion flow
   Duration: ~30-60 seconds

✅ Profiling complete!
...
```

Wait for completion, then view results.

---

## Step 4: Analyze Results

### View Text Report
```bash
stackprof tmp/stackprof-chat.dump
```

**Example output:**
```
Mode: cpu(1000)
Samples: 5421 (0.00% miss rate)
GC: 312 (5.75%)
     TOTAL    (pct)     SAMPLES    (pct)     FRAME
      5421 (100.0%)        5421 (100.0%)     (garbage collection)
      2145 (39.6%)        2145 (39.6%)     enrich_list_structure_with_planning
      1205 (22.2%)        1205 (22.2%)     RubyLLM::Chat#complete
       892 (16.5%)         892 (16.5%)     ListItem.insert_all
       654 (12.1%)         654 (12.1%)     JSON.parse
```

### View Interactive HTML Graph (Better)
```bash
stackprof --d3 tmp/stackprof-chat.dump > tmp/profile.html
open tmp/profile.html
```

This shows a clickable flame graph where you can zoom into methods.

---

## Step 5: Identify Your Bottleneck

Based on the profiler output, your situation is one of these:

### Scenario A: LLM Calls Dominate (>60%)
```
22.2% - RubyLLM::Chat#complete
16.4% - RubyLLM HTTP call
12.1% - JSON parsing
```

**Problem:** Multiple sequential LLM calls
**Solution:** See "Fix A: Parallelize & Cache LLM Calls"

### Scenario B: Database Inserts Dominate (>40%)
```
16.5% - ListItem.insert_all
12.3% - List.create
 8.4% - Chat.update
```

**Problem:** Sequential database inserts (30+ separate INSERTs)
**Solution:** See "Fix B: Batch Database Inserts"

### Scenario C: Enrichment Dominates (>50%)
```
39.6% - enrich_list_structure_with_planning
22.2% - generate_location_specific_items
16.5% - generate_phase_specific_items
```

**Problem:** Sequential location/phase item generation
**Solution:** See "Fix C: Parallelize Enrichment"

---

## Fix A: Parallelize & Cache LLM Calls

### Why Sequential is Slow
```
Intent detection (1-2s) ──────────────────┐
                                           ├─ Sequential = 4-6s total
Parameter extraction (1-2s) ──────────────┤
                                           │
Enrichment (1-2s) ───────────────────────┤
                                           │
Main response (1-2s) ─────────────────────┘
```

### Why Parallel is Fast
```
Intent detection (1-2s) ┐
Parameter extraction (0.5-1s) │ Concurrent::Future.execute
Enrichment (1-2s) ────────────├─ max(1-2s, 0.5-1s, 1-2s) = ~2s total
Main response (1-2s) ─────────┘
```

### Implementation

**File:** `app/services/chat_completion_service.rb`

Add at the top:
```ruby
require 'concurrent'
```

In method `check_parameters_for_intent` (around line 117):

**Before (sequential):**
```ruby
param_result = ParameterExtractionService.new(
  user_message: @user_message,
  intent: intent,
  context: @context
).call
```

**After (parallel fallback):**
```ruby
# Run parameter extraction with timeout
param_future = Concurrent::Future.execute do
  ParameterExtractionService.new(
    user_message: @user_message,
    intent: intent,
    context: @context
  ).call
end

param_result = param_future.value(timeout: 3)
return nil unless param_result&.success?
```

**Impact:** Saves 0.5-1s if other code can run in parallel

### Cache Results

**File:** `app/services/ai_intent_router_service.rb`

Around line 33 in `detect_intent_with_llm`:

```ruby
def detect_intent_with_llm
  # Cache key based on message hash
  cache_key = "intent:#{Digest::SHA256.hexdigest(@user_message.content)}"

  Rails.cache.fetch(cache_key, expires_in: 7.days) do
    # ... existing LLM call code ...
  end
end
```

**Impact:** Eliminates 10-15% of LLM calls on repeated patterns

---

## Fix B: Batch Database Inserts

### Why Sequential is Slow
```
INSERT list (1ms)
  ├─ INSERT item 1 (1ms)
  ├─ INSERT item 2 (1ms)
  ├─ INSERT item 3 (1ms)
  └─ ... 25 more items = ~30ms for items
INSERT sublist 1 (1ms)
  ├─ INSERT nested item 1 (1ms)
  ├─ INSERT nested item 2 (1ms)
  └─ ... more items
Total: ~60-100 individual queries
```

### Why Batch is Fast
```
INSERT list (1ms)
INSERT all items in one batch (3ms)
INSERT all sublists in one batch (2ms)
INSERT all nested items in one batch (4ms)
Total: ~10ms (90% faster!)
```

### Implementation

**File:** `app/services/chat_completion_service.rb`

Find method `handle_list_creation` (around line 668)

**Replace the item insertion loop:**

Instead of:
```ruby
params[:items].each do |item|
  ListItem.create!(list: list, title: item[:title], ...)
end
```

Use:
```ruby
if params[:items].present?
  item_rows = params[:items].map do |item_data|
    {
      list_id: list.id,
      owner_id: @context.user.id,
      organization_id: @context.organization.id,
      title: item_data[:title] || item_data["title"],
      description: item_data[:description] || item_data["description"],
      created_at: Time.current,
      updated_at: Time.current
    }
  end
  ListItem.insert_all(item_rows)
  Rails.logger.debug("Batch inserted #{item_rows.length} items")
end
```

Do the same for nested items.

**Impact:** 30-40 sequential inserts → 3-4 batch inserts = **90% faster**

---

## Fix C: Parallelize Enrichment

### Why Sequential is Slow
```
Generate items for location 1 (2s) ──────────┐
Generate items for location 2 (2s) ──────────├─ Sequential = 6s total
Generate items for location 3 (2s) ──────────┘
```

### Why Parallel is Fast
```
Generate items for location 1 (2s) ┐
Generate items for location 2 (2s) ├─ Concurrent = ~2s total
Generate items for location 3 (2s) ┘
```

### Implementation

**File:** `app/services/chat_completion_service.rb`

Find method `enrich_list_structure_with_planning`:

```ruby
def enrich_list_structure_with_planning(base_params:, planning_params:)
  require 'concurrent'

  enriched = base_params.dup

  # Parallelize location item generation
  if planning_params[:locations].present?
    location_futures = planning_params[:locations].map do |location|
      Concurrent::Future.execute do
        generate_location_specific_items(location, base_params[:category])
      end
    end

    location_items = location_futures.map { |f| f.value(timeout: 10) }
    enriched[:location_items] = location_items
  end

  # Parallelize phase item generation
  if planning_params[:phases].present?
    phase_futures = planning_params[:phases].map do |phase|
      Concurrent::Future.execute do
        generate_phase_specific_items(phase, base_params[:category])
      end
    end

    phase_items = phase_futures.map { |f| f.value(timeout: 10) }
    enriched[:phase_items] = phase_items
  end

  enriched
end
```

**Impact:** 3 locations taking 2s each = 6s sequential → ~2s parallel

---

## Fix D: Form Persistence Bug

### The Problem
Pre-creation planning form stays on screen after user submits answers. Should be removed and replaced with assistant response.

### Root Cause
Form is rendered as part of the user's message. When the assistant response comes back via Turbo Stream, it only replaces the loading indicator, leaving the form visible.

### Solution: Stimulus Controller

**Create:** `app/javascript/controllers/chat_form_controller.js`

```javascript
import { Controller } from "@hotwire/stimulus"

export default class extends Controller {
  connect() {
    // When new messages arrive via Turbo Stream, remove old forms
    document.addEventListener("turbo:after-stream-render", () => {
      this.cleanupOldForms()
    })
  }

  cleanupOldForms() {
    // Find all chat message containers
    const messages = document.querySelectorAll('.chat-message-container')

    // If we have multiple messages, remove forms from older ones
    if (messages.length > 1) {
      Array.from(messages).slice(0, -2).forEach(msg => {
        const form = msg.querySelector('[id^="pre-creation-planning-form-"]')
        if (form) {
          form.closest('.bg-blue-50')?.remove()
        }
      })
    }
  }

  cancel(e) {
    e.preventDefault()
    // Remove form when user clicks cancel
    const form = e.target.closest('[id^="pre-creation-planning-form-"]')
    form?.closest('.chat-message-container')?.remove()
  }
}
```

**Update:** `app/views/message_templates/_pre_creation_planning.html.erb`

Add `data-controller` to root element:

```erb
<div class="text-xs bg-blue-50 rounded-lg p-4 border border-blue-200"
     data-controller="chat-form">
  <!-- existing content -->
  <button type="button"
          data-action="chat-form#cancel">
    Cancel
  </button>
</div>
```

**Verify:** After answering questions, form disappears and only assistant response shows.

---

## Implementation Order

### Phase 1: Analysis (30 minutes)
1. Install stackprof
2. Create profiling task
3. Run profiler
4. Analyze output
5. Identify which fix(es) to apply

### Phase 2: Form Bug (20 minutes)
1. Create Stimulus controller
2. Update template
3. Test that form removes properly

### Phase 3: Optimization (30-90 minutes based on bottleneck)
- Apply Fix A, B, C as needed based on profiler results
- Run tests to verify no regressions
- Re-run profiler to confirm improvement

### Phase 4: Verify (15 minutes)
1. Run full test suite
2. Check for N+1 queries (Bullet gem)
3. Manual testing in browser

---

## Profiling Output Interpretation

### What to Look For

**If you see:**
```
22.2% - RubyLLM::Chat#complete
16.4% - RubyLLM HTTP call
12.1% - JSON parsing
= 50.7% total
```
→ **LLM calls are bottleneck** → Apply Fix A

**If you see:**
```
16.5% - ListItem.insert_all
12.3% - List.create
 8.4% - Chat.update
= 37.2% total
```
→ **Database is bottleneck** → Apply Fix B

**If you see:**
```
39.6% - enrich_list_structure_with_planning
22.2% - generate_location_specific_items
16.5% - generate_phase_specific_items
= 78.3% total
```
→ **Enrichment is bottleneck** → Apply Fix C

---

## Expected Improvements

| Optimization | Current | After | Savings |
|---|---|---|---|
| Fix A: Parallelize LLM | 4-6s | 2-3s | 50-60% |
| Fix B: Batch inserts | 0.5s DB | 0.05s DB | 90% |
| Fix C: Parallel enrichment | 6s enrichment | 2s enrichment | 67% |
| Fix D: Form bug | Form stuck | Instant removal | 100% |

**Combined Impact:**
- Before: 7-13 seconds total
- After: 2-4 seconds total
- **Improvement: 65-80% faster** 🚀

---

## Tools & Resources

**Profiling Tool:**
- [Stackprof GitHub](https://github.com/tmm1/stackprof)
- Shows CPU usage by method
- Industry standard

**Debugging Tools:**
- Bullet gem (N+1 detection) - already in Gemfile
- Rails debug mode
- Browser DevTools

**Testing:**
- RSpec (already set up)
- Capybara for integration tests
- VCR for recording HTTP interactions

---

## Quick Checklist

**To Get Started:**
- [ ] Read this entire document
- [ ] Install stackprof: `gem "stackprof", require: false` + `bundle install`
- [ ] Create `lib/tasks/profile_chat.rake`
- [ ] Run profiler: `bundle exec rake profile:chat`
- [ ] View results: `stackprof --d3 tmp/stackprof-chat.dump > tmp/profile.html && open tmp/profile.html`
- [ ] Identify which fix(es) to apply

**To Fix Form Bug:**
- [ ] Create Stimulus controller
- [ ] Update template
- [ ] Test in browser

**To Apply Optimization:**
- [ ] Apply Fix A/B/C based on profiler results
- [ ] Run tests: `bundle exec rspec`
- [ ] Re-run profiler to verify improvement

---

## FAQ

**Q: Should I implement all fixes?**
A: No. Start with profiler results. If LLM is 60% of time, Fix A helps most. Apply fixes in order of impact.

**Q: Will parallelization break anything?**
A: Unlikely if you use proper timeouts. Test with `bundle exec rspec` first.

**Q: Do I need Anthropic credits?**
A: No. You're using OpenAI with gpt-5-nano/gpt-5. Haiku optimization is optional for future.

**Q: How do I know if optimization worked?**
A: Re-run profiler after changes. See which methods decreased.

**Q: What if nothing changed?**
A: You may have optimized the wrong bottleneck. Re-check profiler output.

---

## Need Help?

1. **Profiler output confusing?** → Review "Profiling Output Interpretation"
2. **Don't know which fix to apply?** → The profiler will tell you (biggest box)
3. **Tests failing?** → Check batch insert fields, concurrent timeouts
4. **Performance didn't improve?** → Re-run profiler to verify optimization was applied

---

## Next Steps

Start here:
```bash
# 1. Install
echo 'gem "stackprof", require: false' >> Gemfile && bundle install

# 2. Create task (copy code from Step 2 above)
# 3. Run profiler
bundle exec rake profile:chat

# 4. View results
stackprof --d3 tmp/stackprof-chat.dump > tmp/profile.html && open tmp/profile.html

# 5. Apply fixes based on output
```

Share the profiler results and we'll apply the right optimizations! 🎯

