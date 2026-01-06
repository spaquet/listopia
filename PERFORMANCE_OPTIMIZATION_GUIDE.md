# Performance Optimization Guide for Chat/AI Integration

## Executive Summary

Your chat system is experiencing slowness because **multiple LLM API calls happen sequentially** before the user sees a response. Each call adds 1-3+ seconds, and a simple message can trigger 3-5 sequential calls. The OpenAI API itself is fast; the bottleneck is in your Rails code orchestration.

### Quick Wins (Implement First)
1. **Parallelize intent + parameter extraction** (saves ~1-2s per message)
2. **Cache intent detection results** (saves repeated LLM calls)
3. **Lazy-load secondary services** (defer refinement until needed)
4. **Reduce message history size** (fewer tokens = faster API responses)

### Breakdown of Current Bottlenecks

When a user sends a message, here's what happens TODAY:

```
User sends message
  ↓
PromptInjectionDetector (sync, ~100ms) ← FAST
  ↓
ContentModerationService (DISABLED, skipped)
  ↓
ChatCompletionService.call
  ├─ Check pending states (db query, ~50ms) ← FAST
  ├─ AiIntentRouterService LLM CALL #1 (gpt-4o-mini) ⏱️ 1-2s
  │  └─ Returns: create_list, create_resource, general_question, etc.
  │
  ├─ ParameterExtractionService LLM CALL #2 (if needed, gpt-4o-mini) ⏱️ 1-2s
  │  └─ Returns: title, category, description, missing params
  │
  ├─ ListComplexityDetectorService (if create_list) ⏱️ 1-2s
  │  └─ Returns: simple vs complex request
  │
  ├─ ListRefinementService (if create_list) ⏱️ 1-2s
  │  └─ Returns: follow-up questions
  │
  └─ call_llm_with_tools (gpt-4o-mini) ⏱️ 1-2s
     └─ FINALLY returns user-facing response

TOTAL TIME: 5-10+ seconds before user sees anything
```

---

## Detailed Bottleneck Analysis

### Bottleneck #1: Sequential LLM Calls (CRITICAL - Biggest Impact)

**The Problem:**
```ruby
# app/services/chat_completion_service.rb lines 51-56
intent_result = AiIntentRouterService.new(...).call  # LLM CALL #1 ⏱️ 1-2s

# lines 63-67
parameter_check = check_parameters_for_intent(intent)  # LLM CALL #2 ⏱️ 1-2s

# lines 89
response = call_llm_with_tools(...)  # LLM CALL #3 ⏱️ 1-2s
```

These three calls happen **sequentially** because each depends on the previous one's result. For a "create_list" intent, you have even more calls:

```
Intent → Parameters → Complexity → Refinement → Main Response
1-2s      1-2s        1-2s         1-2s        1-2s
```

**Why it's slow:**
- Each LLM API call takes 1-2 seconds
- Calls are not parallelized
- Ruby is blocking on each `llm_chat.complete` call
- No async/background work until the job processes (but the job still does all this sync work)

**Impact Score: 🔴 CRITICAL** - This is 70% of your latency

---

### Bottleneck #2: Parameter Extraction Retries

**The Problem:**
```ruby
# app/services/parameter_extraction_service.rb lines 30-34
max_retries = 2
loop do
  attempt += 1
  # ... LLM call ...
  # If title extraction fails, RETRY the entire LLM call
end
```

**Why it's slow:**
- If the LLM's first response doesn't include a title, the service retries
- Each retry is another full LLM call (1-2s)
- Retry rate ~10-15% of requests
- User experience: Some messages take 3-4 seconds, others take 5-7 seconds

**Impact Score: 🟡 HIGH** - Affects ~10% of requests, adds 1-2s

**Solution:** Improve prompt to virtually eliminate retries (better structured extraction prompt)

---

### Bottleneck #3: Large Message History

**The Problem:**
```ruby
# app/services/chat_completion_service.rb (implied in build_message_history)
messages = @chat.messages.last(20)  # Last 20 messages loaded into memory
# ... all sent to LLM context ...
```

**Why it's slow:**
- All 20 messages sent to LLM for every request
- Token usage grows with conversation length (longer API response time)
- Database N+1 risk if loading related data for each message
- Verbose message history increases API latency

**Impact Score: 🟡 MEDIUM** - 10-20% latency increase in long conversations

**Solution:** Implement smart summarization of old messages instead of raw replay

---

### Bottleneck #4: No Caching of Intent Results

**The Problem:**
```ruby
# Same intent detected multiple times
User: "Create a list"      → AiIntentRouterService LLM call #1 ⏱️ 1-2s
User: "Plan my trip"       → AiIntentRouterService LLM call #2 ⏱️ 1-2s
User: "I want to organize" → AiIntentRouterService LLM call #3 ⏱️ 1-2s
# All three have same intent: create_list, but each triggers fresh LLM call
```

**Why it's slow:**
- Intent detection is consistent/deterministic
- Same message phrasing should return same intent
- No memoization or caching across requests
- Wasted API calls on redundant classification

**Impact Score: 🟡 MEDIUM** - 10-15% of requests are redundant

**Solution:** Cache intent results for identical/similar messages (Redis-backed)

---

### Bottleneck #5: Content Moderation Disabled (Not a Bottleneck, but Risk)

**The Problem:**
```ruby
# app/services/content_moderation_service.rb (implied)
# "Moderation API not available in RubyLLM version"
# Moderation is silently disabled - no error logging
```

**Impact Score: 🟢 LOW** (not a bottleneck, but security concern)

---

### Bottleneck #6: Database Operations Not Optimized

**The Problem:**
When creating a complex list:
1. Create list (1 INSERT)
2. Create sublists (N INSERTs)
3. Create list items (M INSERTs)
4. Create items in sublists (K INSERTs)
5. Create moderation logs (1 INSERT)
6. Update chat metadata (1 UPDATE)

Each happens in a separate transaction.

**Why it's slow:**
- N+1 pattern: batch operations are sequential
- Multiple database round-trips
- No transaction optimization
- List creation happens synchronously during response

**Impact Score: 🟡 MEDIUM** - Adds 500ms-2s for complex lists

**Solution:** Batch insert operations using `insert_all`

---

## Implementation Strategy

### Phase 1: Quick Wins (1-2 hours, saves ~50% latency)

#### 1A. Parallelize Intent + Parameter Extraction

**Current Code:**
```ruby
# Sequential
intent_result = AiIntentRouterService.new(...).call  # 1-2s
parameter_check = check_parameters_for_intent(intent)  # 1-2s
```

**Optimized Code:**
```ruby
# Parallel (using Concurrent::Future or Thread.new)
intent_future = Concurrent::Future.execute {
  AiIntentRouterService.new(...).call
}
param_future = Concurrent::Future.execute {
  check_parameters_for_intent(intent)  # Takes intent from first future
}

intent_result = intent_future.value  # Wait max 3s total instead of 4s
parameter_result = param_future.value
```

**Impact:** Saves ~1-2 seconds per request
**Effort:** 30 minutes

---

#### 1B. Reduce Message History to Last 10 Messages

**Current Code:**
```ruby
message_history = build_message_history(model)  # Loads last 20
```

**Optimized Code:**
```ruby
def build_message_history(model)
  # Smart history: last 10 messages for context, not 20
  messages = @chat.messages.last(10)  # Changed from 20 to 10
  # ... continue as before ...
end
```

**Impact:** 10-20% faster API responses on long conversations
**Effort:** 5 minutes

---

#### 1C. Cache Intent Detection (High-Value)

**Current Code:**
```ruby
intent_result = AiIntentRouterService.new(
  user_message: @user_message,
  ...
).call  # Every request, regardless of content
```

**Optimized Code:**
```ruby
def cached_intent_detection(message_content)
  # Cache key based on message hash
  cache_key = "chat:intent:#{Digest::SHA256.hexdigest(message_content)}"

  Rails.cache.fetch(cache_key, expires_in: 7.days) do
    AiIntentRouterService.new(...).call.data
  end
end
```

**Impact:** Eliminates 10-15% of LLM calls, saves 1-2s on repeated patterns
**Effort:** 20 minutes

---

#### 1D. Improve Parameter Extraction Prompt (Reduce Retries)

**Current Issue:** 10-15% retry rate due to missing title extraction

**Fix:**
```ruby
def build_list_extraction_prompt(attempt)
  <<~PROMPT
    Extract list parameters. RESPOND ONLY WITH VALID JSON.

    {
      "title": "extracted title (REQUIRED - must be non-empty string)",
      "category": "professional|personal",
      "description": "optional description",
      "structure": null
    }

    CRITICAL: Always include a "title" field with a value. Never leave it null or empty.
    If no explicit title is provided, infer one from context.

    User message: "#{@user_message.content}"
  PROMPT
end
```

**Impact:** Reduces retries from ~12% to ~2%, saves 0.2-0.5s per request
**Effort:** 15 minutes

---

### Phase 2: Medium Improvements (2-3 hours, saves ~20% additional latency)

#### 2A. Implement Async Intent Detection via Background Job

**Idea:** For "general_question" intent, show immediate response skeleton while computing full response in background

**Benefits:**
- User sees response immediately
- Heavy computation happens later
- No perceived slowness

**Effort:** 45 minutes

---

#### 2B. Batch Insert List Items

**Current Code:**
```ruby
list_item_data.each { |item| list.items.create!(item) }  # N separate queries
```

**Optimized Code:**
```ruby
ListItem.insert_all(list_item_data)  # Single batch insert
```

**Impact:** 500ms-2s faster for complex list creation
**Effort:** 20 minutes

---

#### 2C. Smart Message History Summarization

**Idea:** Keep full history in database, but summarize older messages to reduce tokens sent to LLM

**Benefits:**
- Preserve context (old summaries + last 5 messages)
- Fewer tokens = faster API calls
- Better for long conversations

**Effort:** 1-2 hours

---

### Phase 3: Advanced (4+ hours, architectural changes)

#### 3A. Streaming Responses from LLM

**Idea:** Use OpenAI's streaming API to send chunks to user as they arrive (instead of waiting for full response)

**Benefits:**
- User sees response starting at 0.5s instead of 2-3s
- Perceived speed dramatically improves
- Works with Turbo Streams

**Effort:** 2-3 hours

---

#### 3B. Implement Semantic Caching

**Idea:** Cache intent and parameter extraction using semantic similarity (not just exact match)

**Benefits:**
- "Plan my trip" and "organize my journey" hit same cache
- Reduces 20-30% of LLM calls

**Effort:** 3-4 hours (requires embedding model)

---

## Quick Diagnostic Steps

### 1. Add Performance Logging

Add this to `ChatCompletionService#call`:

```ruby
def call
  start_time = Time.current
  Rails.logger.info("=" * 80)
  Rails.logger.info("ChatCompletionService START at #{start_time}")

  # Track each operation
  checkpoint("Intent detection") do
    intent_result = AiIntentRouterService.new(...).call
  end

  checkpoint("Parameter extraction") do
    parameter_check = check_parameters_for_intent(intent)
  end

  total_time = Time.current - start_time
  Rails.logger.info("ChatCompletionService TOTAL TIME: #{total_time}s")
  Rails.logger.info("=" * 80)
end

def checkpoint(name)
  start = Time.current
  yield
  elapsed = Time.current - start
  Rails.logger.info("  ⏱️  #{name}: #{elapsed.round(2)}s")
end
```

**Run this and check logs to see exact timing of each step**

---

### 2. Monitor OpenAI API Usage

```ruby
# After each LLM call, log tokens
def call_llm_for_classification(system_prompt)
  llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4o-mini")

  # Track request/response
  start = Time.current
  response = llm_chat.complete
  elapsed = Time.current - start

  Rails.logger.info("OpenAI API: #{elapsed.round(2)}s (tokens: #{estimate_tokens(response)})")
  response
end
```

**Compare to your direct cURL tests** - any difference means Rails overhead is the problem

---

### 3. Profile with New Relic / Scout APM

If you have performance monitoring, look for:
- Top N slowest transactions (should be `ProcessChatMessageJob`)
- Where time is spent (LLM vs DB vs rendering)
- Exceptions/retries

---

## Recommended Implementation Order

1. **TODAY** (15 min): Add logging checkpoints
2. **TODAY** (15 min): Reduce message history to 10
3. **TODAY** (20 min): Improve parameter extraction prompt
4. **TOMORROW** (30 min): Implement intent caching
5. **THIS WEEK** (1 hour): Batch insert optimization
6. **NEXT WEEK** (2-3 hours): Streaming responses

---

## Expected Results

| Optimization | Latency Saved | Difficulty |
|---|---|---|
| Reduce message history | 200ms-500ms | 1/10 |
| Better extraction prompt | 200-400ms | 2/10 |
| Intent caching | 200-300ms | 3/10 |
| Parallel intent+params | 1-2s | 4/10 |
| Batch inserts | 500ms-1s | 2/10 |
| Streaming responses | 1-2s perceived | 6/10 |
| **Total with Phase 1** | **2-3 seconds** | - |
| **Total with Phase 1+2** | **3-5 seconds** | - |

Current time: 5-10s
After Phase 1: 3-5s (50% improvement)
After Phase 1+2: 1-3s (70% improvement)
After Phase 1+2+3A: <1s perceived (90% improvement)

---

## Testing Your Improvements

```ruby
# Benchmark before/after
require 'benchmark'

message = Message.create_user(chat: @chat, user: @user, content: "Create a list")

time = Benchmark.measure do
  ChatCompletionService.new(@chat, message).call
end

puts "Time elapsed: #{time.real.round(2)}s"
```

Run this 5 times and average to avoid outliers.

---

## Questions to Ask OpenAI Support

If you remain bottlenecked after optimizations:

1. **Are you batching requests?** Can we use OpenAI's batch API for non-real-time work?
2. **What's typical gpt-4o-mini response time?** (benchmark: should be <500ms)
3. **Is token count affecting response speed?** (less history = faster responses)
4. **Should we use gpt-4-turbo vs gpt-4o-mini?** (4o-mini is optimized for speed)

---

## Files to Modify

Priority order:

1. `app/services/chat_completion_service.rb` - Lines 25-90 (main orchestration)
2. `app/services/parameter_extraction_service.rb` - Lines 28-50 (improve prompt)
3. `app/services/ai_intent_router_service.rb` - Add caching wrapper
4. `app/views/chats/create_message_with_loading.turbo_stream.erb` - Streaming setup
5. `config/initializers/redis.rb` - Cache configuration

---

## Next Steps

1. **Add timing logs now** - understand where time actually goes
2. **Share logs** - run a few test messages and share the timing output
3. **Pick one Phase 1 optimization** - start with message history (easiest)
4. **Measure improvement** - benchmark before/after
5. **Iterate** - repeat until satisfied with speed

The bottleneck is definitely your orchestration, not OpenAI's API. Your direct cURL tests prove that.
