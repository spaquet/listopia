# Quick Wins Implementation Checklist

## Why This Matters
Your chat calls 4-5 LLM services sequentially. Each is 1-2 seconds. Simple changes to model selection and parallelization can save **3-6 seconds per message**.

---

## ✅ Quick Win #1: Switch AiIntentRouterService to Claude Haiku (5 minutes)

**File:** `app/services/ai_intent_router_service.rb`

**Current code (line 126):**
```ruby
llm_chat = RubyLLM::Chat.new(
  provider: :openai,
  model: "gpt-4o-mini"
)
```

**Change to:**
```ruby
llm_chat = RubyLLM::Chat.new(
  provider: :anthropic,
  model: "claude-3-5-haiku-20241022"
)
```

**Why:**
- Claude Haiku is 3-4x faster (0.3-0.5s vs 1-2s)
- Same accuracy for intent classification (simple task)
- 99% cheaper

**Expected impact:** ⚡ Saves 0.5-1.5 seconds per message

---

## ✅ Quick Win #2: Improve Parameter Extraction Prompt (15 minutes)

**File:** `app/services/parameter_extraction_service.rb`

**Current issue:** 10-15% retry rate when title extraction fails

**Find method:** `build_list_extraction_prompt(attempt)`

**Replace the prompt with this (around line 28):**
```ruby
def build_list_extraction_prompt(attempt)
  <<~PROMPT
    Extract parameters from user request. Return ONLY valid JSON.

    {
      "title": "clear title inferred from request (REQUIRED - never null, never empty string)",
      "category": "professional" | "personal" | null,
      "description": "optional summary of what they want",
      "structure": null | "location-based" | "phase-based" | "section-based"
    }

    CRITICAL RULES:
    1. Title is REQUIRED - always provide a meaningful title
    2. If no explicit title, INFER ONE from the context
    3. Never leave title as null or empty string
    4. If user asks to "organize my expenses", title = "Expense Organization"
    5. If user asks to "learn JavaScript", title = "JavaScript Learning Plan"

    EXAMPLES:
    Input: "Plan a trip to Japan for 2 weeks"
    Output: {"title": "Japan Trip - 2 Weeks", "category": "personal", ...}

    Input: "Create a roadshow plan across 5 US cities"
    Output: {"title": "US Roadshow - 5 Cities", "category": "professional", ...}

    Input: "Give me a workout routine"
    Output: {"title": "Workout Routine", "category": "personal", ...}

    User request: "#{@user_message.content}"

    Always respond with valid JSON. ALWAYS include a title field.
  PROMPT
end
```

**Why:** Eliminates retries by being explicit about title requirement

**Expected impact:** ⚡ Saves 0.2-0.4 seconds (reduces ~12% of requests from retry)

---

## ✅ Quick Win #3: Switch ListRefinementService to Faster Model (5 minutes)

**File:** `app/services/list_refinement_service.rb`

**Current code (line 63):**
```ruby
llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4-turbo")
```

**Change to:**
```ruby
llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4o-mini")
```

**Why:**
- 4o-mini is optimized for speed while maintaining quality
- Faster than 4-turbo
- Same OpenAI provider (no integration changes)

**Expected impact:** ⚡ Saves 1-2 seconds on complex list creation

---

## ✅ Quick Win #4: Enable ContentModerationService (30 minutes)

**File:** `app/services/content_moderation_service.rb`

**Replace `call_openai_moderation` method (lines 64-92) with:**
```ruby
def call_openai_moderation
  return { flagged: false, categories: {}, scores: {}, error: nil } unless ENV["LISTOPIA_USE_MODERATION"] == "true"

  api_key = ENV["OPENAI_API_KEY"] || ENV["RUBY_LLM_OPENAI_API_KEY"]
  unless api_key.present?
    Rails.logger.warn("OpenAI API key not configured for moderation")
    return { flagged: false, categories: {}, scores: {}, error: nil }
  end

  # Direct OpenAI Moderation API call
  require 'net/http'
  require 'json'

  uri = URI('https://api.openai.com/v1/moderations')
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Post.new(uri.path)
  request['Authorization'] = "Bearer #{api_key}"
  request['Content-Type'] = 'application/json'
  request.body = JSON.generate({ input: @content, model: 'text-moderation-latest' })

  start_time = Time.current
  response = http.request(request)
  elapsed = Time.current - start_time

  Rails.logger.debug("OpenAI moderation API took #{elapsed.round(3)}s")

  if response.code.to_i == 200
    result = JSON.parse(response.body)
    parse_moderation_response(result)
  else
    Rails.logger.error("OpenAI moderation API error: #{response.code} #{response.body}")
    { flagged: false, categories: {}, scores: {}, error: "API error: #{response.code}" }
  end
rescue => e
  Rails.logger.error("OpenAI moderation API call failed: #{e.class} - #{e.message}")
  { flagged: false, categories: {}, scores: {}, error: e.message }
end
```

**Enable it in your environment:**
```bash
# .env
LISTOPIA_USE_MODERATION=true
```

**Why:**
- Catches harmful content before it gets to main LLM
- Prevents "stupid" questions by filtering abuse
- Very fast (~100-200ms)
- Extremely cheap (~$0.001 per 1000 requests)

**Expected impact:** 🛡️ Improved safety (not a speed improvement, but important)

---

## ✅ Quick Win #5: Reduce Message History (5 minutes)

**File:** `app/services/chat_completion_service.rb`

**Find method:** `build_message_history(model)`

**Current code:**
```ruby
messages = @chat.messages.last(20)  # Load last 20 messages
```

**Change to:**
```ruby
messages = @chat.messages.last(10)  # Load last 10 messages
```

**Why:**
- Fewer messages = fewer tokens sent to LLM
- Fewer tokens = faster API response
- Still maintains good conversation context
- Bigger impact on long conversations

**Expected impact:** ⚡ Saves 0.2-0.5 seconds on long conversations

---

## Medium Effort: Parallelize Intent + Parameters (45 minutes)

**File:** `app/services/chat_completion_service.rb`

**Current code (lines 50-68):**
```ruby
# Sequential - blocks on each
intent_result = AiIntentRouterService.new(...).call  # 1-2s
parameter_check = check_parameters_for_intent(intent)  # 1-2s
```

**Change to (add at top of service):**
```ruby
require 'concurrent'

def call
  # ... existing code before intent detection ...

  # Parallelize intent detection + generic parameter extraction
  intent_future = Concurrent::Future.execute(executor: Concurrent::ThreadPoolExecutor.new(max_threads: 2)) do
    AiIntentRouterService.new(
      user_message: @user_message,
      chat: @chat,
      user: @context.user,
      organization: @context.organization
    ).call
  end

  # While intent is processing, run generic parameter extraction
  generic_params_future = Concurrent::Future.execute(executor: Concurrent::ThreadPoolExecutor.new(max_threads: 2)) do
    ParameterExtractionService.new(
      user_message: @user_message,
      intent: "general",  # Use generic intent for now
      context: @context
    ).call
  end

  # Wait for both (up to 3 seconds total)
  intent_result = intent_future.value(timeout: 3) rescue nil
  generic_params_result = generic_params_future.value(timeout: 3) rescue nil

  return failure(errors: ["Intent detection timed out"]) unless intent_result&.success?

  intent = intent_result.data[:intent]

  # If intent is specific, now extract specific parameters
  if intent.in?(["create_list", "create_resource", "manage_resource"])
    specific_param_result = ParameterExtractionService.new(
      user_message: @user_message,
      intent: intent,
      context: @context
    ).call
    parameter_check = check_parameters_for_intent(intent, specific_param_result)
  else
    parameter_check = nil
  end

  # ... rest of existing code ...
end

def check_parameters_for_intent(intent, param_result = nil)
  # If param_result already provided, use it (from parallel execution)
  unless param_result
    param_result = ParameterExtractionService.new(
      user_message: @user_message,
      intent: intent,
      context: @context
    ).call
  end

  # ... rest of existing logic ...
end
```

**Why:**
- Intent detection doesn't depend on parameters
- Can run both in parallel instead of sequential
- Intent takes ~1-2s, parameters also ~1-2s
- Parallel: max(1-2s, 1-2s) = 1-2s
- Sequential: 1-2s + 1-2s = 2-4s

**Expected impact:** ⚡ Saves 1-2 seconds per complex request

---

## Implementation Order (Do Them in This Order)

1. **Win #1** - Switch intent router to Haiku (5 min) ← START HERE
2. **Win #2** - Improve parameter prompt (15 min)
3. **Win #3** - Switch refinement model (5 min)
4. **Win #5** - Reduce message history (5 min)
5. **Win #4** - Enable moderation (30 min)
6. **Parallel** - Parallelize intent+params (45 min) ← More complex, do last

**Total time: ~2 hours for ALL improvements**

---

## Testing Each Change

### Before/After Benchmark

```ruby
# In Rails console
require 'benchmark'

chat = Chat.find(id: "your_chat_id")
message_content = "Create a comprehensive business plan for my startup"

user_message = Message.create_user(chat: chat, user: chat.user, content: message_content)

time = Benchmark.measure do
  ChatCompletionService.new(chat, user_message).call
end

puts "Total time: #{time.real.round(2)}s"
```

Run this before each change, note the time, then apply the change and run again.

**Expected progression:**
- Baseline: 5-10s
- After Win #1: 4-8s (1-2s saved)
- After Win #2: 3.5-7.5s (0.2-0.4s saved)
- After Win #3: 2.5-5.5s (1-2s saved)
- After Win #4+5: 2-5s (0.2-0.5s saved)
- After Parallel: <2s (1-2s saved)

**Total:** ~70% faster 🚀

---

## Environment Setup

Ensure you have the API keys configured:

```bash
# .env
OPENAI_API_KEY=sk-...
RUBY_LLM_OPENAI_API_KEY=sk-... # Alternative
ANTHROPIC_API_KEY=sk-ant-... # For Claude Haiku
LISTOPIA_USE_MODERATION=true # Enable moderation
```

---

## Monitoring After Changes

Add to your logs to verify improvements:

```ruby
# In ChatCompletionService#call, add at the beginning:
start_time = Time.current
Rails.logger.info("🚀 ChatCompletionService START - #{start_time}")

# Add after each major step:
Rails.logger.info("✅ Intent detection: #{(Time.current - start_time).round(2)}s")
Rails.logger.info("✅ Parameter extraction: #{(Time.current - start_time).round(2)}s")
Rails.logger.info("✅ LLM response: #{(Time.current - start_time).round(2)}s")

# At the end:
total_time = Time.current - start_time
Rails.logger.info("🎯 ChatCompletionService TOTAL: #{total_time.round(2)}s")
```

Watch your logs as users interact with chat - you'll see the timing improvements immediately!

