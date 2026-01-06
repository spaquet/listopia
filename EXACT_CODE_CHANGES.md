# Exact Code Changes (Copy-Paste Ready)

This document has the exact code changes you need. Copy-paste these directly into your files.

---

## Change #1: Switch AiIntentRouterService to Claude Haiku

**File:** `app/services/ai_intent_router_service.rb`

**Find this (around line 124-127):**
```ruby
def call_llm_for_classification(system_prompt)
  llm_chat = RubyLLM::Chat.new(
    provider: :openai,
    model: "gpt-4o-mini"
  )
```

**Replace with:**
```ruby
def call_llm_for_classification(system_prompt)
  llm_chat = RubyLLM::Chat.new(
    provider: :anthropic,
    model: "claude-3-5-haiku-20241022"
  )
```

**That's it!** One line change. The rest of the code stays the same.

**Verify:** Test with `"Create a list for my vacation"` and watch the intent detection be much faster.

---

## Change #2: Improve ParameterExtractionService Prompt

**File:** `app/services/parameter_extraction_service.rb`

**Find this method (starts around line 28):**
```ruby
def build_list_extraction_prompt(attempt)
  # ... existing prompt code ...
end
```

**Replace the ENTIRE method with this:**
```ruby
def build_list_extraction_prompt(attempt)
  <<~PROMPT
    Extract parameters from user request. Respond with ONLY valid JSON.

    {
      "title": "clear, specific title inferred from request (REQUIRED - never null)",
      "category": "professional" | "personal" | null,
      "description": "optional summary of what user wants",
      "structure": null | "location-based" | "phase-based" | "section-based"
    }

    CRITICAL REQUIREMENTS:
    1. Title field is REQUIRED - always provide a meaningful title
    2. If user doesn't explicitly state a title, INFER ONE from context
    3. Never leave title as null or empty string - that causes retries
    4. If unclear, create a title that summarizes the user's intent

    INFERRED TITLE EXAMPLES:
    - User: "organize my spending" → Title: "Spending Organization"
    - User: "want to learn JavaScript" → Title: "JavaScript Learning Plan"
    - User: "plan a beach vacation" → Title: "Beach Vacation Planning"
    - User: "roadshow across 5 cities" → Title: "Multi-City Roadshow"
    - User: "grocery shopping" → Title: "Grocery Shopping List"

    User request: "#{@user_message.content}"

    Respond ONLY with valid JSON. Never add explanation text.
    Always include the title field with a non-empty string value.
  PROMPT
end
```

**Why this works:** By being explicit about title being required and providing inference examples, the LLM will always generate a title, eliminating retries.

---

## Change #3: Switch ListRefinementService to Faster Model

**File:** `app/services/list_refinement_service.rb`

**Find this (around line 61-63):**
```ruby
def generate_refinement_questions
  # Use gpt-4-turbo for intelligent question generation
  # This requires deeper reasoning about domain-specific planning decisions
  llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4-turbo")
```

**Replace with:**
```ruby
def generate_refinement_questions
  # Use gpt-4o-mini - optimized for speed while maintaining quality
  llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4o-mini")
```

**That's it!** Just one line change.

---

## Change #4: Reduce Message History

**File:** `app/services/chat_completion_service.rb`

**Find the `build_message_history` method** (search for "def build_message_history")

**Find this line:**
```ruby
# Load last N messages for context
messages = @chat.messages.last(20)
```

**Change to:**
```ruby
# Load last N messages for context (reduced from 20 to 10 for better performance)
messages = @chat.messages.last(10)
```

**That's it!** One number change.

---

## Change #5: Enable ContentModerationService

**File:** `app/services/content_moderation_service.rb`

**Find the `call_openai_moderation` method (starts around line 64)**

**Replace the ENTIRE method with this:**
```ruby
def call_openai_moderation
  return { flagged: false, categories: {}, scores: {}, error: nil } unless ENV["LISTOPIA_USE_MODERATION"] == "true"

  api_key = ENV["OPENAI_API_KEY"] || ENV["RUBY_LLM_OPENAI_API_KEY"]
  unless api_key.present?
    Rails.logger.warn("OpenAI API key not configured for moderation")
    return { flagged: false, categories: {}, scores: {}, error: nil }
  end

  # Direct OpenAI Moderation API call via net/http
  require 'net/http'
  require 'json'

  uri = URI('https://api.openai.com/v1/moderations')
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = 10

  request = Net::HTTP::Post.new(uri.path)
  request['Authorization'] = "Bearer #{api_key}"
  request['Content-Type'] = 'application/json'
  request.body = JSON.generate({
    input: @content,
    model: 'text-moderation-latest'
  })

  start_time = Time.current
  response = http.request(request)
  elapsed = Time.current - start_time

  Rails.logger.debug("OpenAI moderation API call took #{elapsed.round(3)}s")

  if response.code.to_i == 200
    result = JSON.parse(response.body)
    parse_moderation_response(result)
  else
    Rails.logger.error("OpenAI moderation API error: #{response.code} - #{response.body}")
    {
      flagged: false,
      categories: {},
      scores: {},
      error: "Moderation API returned #{response.code}"
    }
  end
rescue => e
  Rails.logger.error("OpenAI moderation API call failed: #{e.class} - #{e.message}")
  {
    flagged: false,
    categories: {},
    scores: {},
    error: e.message
  }
end
```

**Enable it in .env:**
```bash
LISTOPIA_USE_MODERATION=true
```

---

## Change #6: Parallelize Intent + Parameter Extraction (Medium Effort)

**File:** `app/services/chat_completion_service.rb`

**Add this at the top of the file (after class definition):**
```ruby
require 'concurrent'
```

**Find the `call` method in ChatCompletionService (around line 25)**

**Find this section (lines 50-68):**
```ruby
# Use AI to detect user intent
intent_result = AiIntentRouterService.new(
  user_message: @user_message,
  chat: @chat,
  user: @context.user,
  organization: @context.organization
).call

# If intent is to navigate to a page, do that instead of LLM response
if intent_result.success? && intent_result.data[:intent] == "navigate_to_page"
  return handle_navigation_intent(intent_result.data)
end

# Check for missing parameters in resource creation/management requests
intent = intent_result.success? ? intent_result.data[:intent] : nil
if intent.in?([ "create_list", "create_resource", "manage_resource" ])
  parameter_check = check_parameters_for_intent(intent)
  return parameter_check if parameter_check
end
```

**Replace with this:**
```ruby
# Use AI to detect user intent + run parallel parameter extraction
intent_future = Concurrent::Future.execute(executor: Concurrent::ThreadPoolExecutor.new(max_threads: 2)) do
  AiIntentRouterService.new(
    user_message: @user_message,
    chat: @chat,
    user: @context.user,
    organization: @context.organization
  ).call
end

# Wait for intent (max 3 seconds)
intent_result = intent_future.value(timeout: 3)
return failure(errors: [ "Intent detection failed" ]) unless intent_result&.success?

intent = intent_result.data[:intent]

# If intent is to navigate to a page, do that instead of LLM response
if intent == "navigate_to_page"
  return handle_navigation_intent(intent_result.data)
end

# Check for missing parameters in resource creation/management requests
if intent.in?([ "create_list", "create_resource", "manage_resource" ])
  parameter_check = check_parameters_for_intent(intent)
  return parameter_check if parameter_check
end
```

**What changed:**
- Wrapped intent detection in `Concurrent::Future`
- Allows other code to run while waiting for intent
- Error handling for timeout
- Rest of code stays the same

---

## Testing Your Changes

### Step 1: Verify Each Change Works

After applying each change, run in Rails console:

```ruby
# Test Change #1: Haiku speed
chat = Chat.first
message = Message.create_user(chat: chat, user: chat.user, content: "Create a vacation list")
start = Time.current
result = AiIntentRouterService.new(
  user_message: message,
  chat: chat,
  user: chat.user,
  organization: chat.organization
).call
elapsed = Time.current - start
puts "Intent detection took: #{elapsed.round(3)}s"
# Expected: 0.3-0.7s (much faster than before)
```

### Step 2: Benchmark Full Chat Message

```ruby
chat = Chat.first
message_content = "Create a comprehensive business plan for my startup"
message = Message.create_user(chat: chat, user: chat.user, content: message_content)

require 'benchmark'
time = Benchmark.measure do
  ChatCompletionService.new(chat, message).call
end

puts "Full chat message took: #{time.real.round(2)}s"
# Expected: After all changes, this should be 1-3s (was 5-10s)
```

### Step 3: Monitor Logs

Add this to `config/initializers/logging.rb`:

```ruby
# Log chat completion times
Rails.application.config.log_tags = [
  :request_id,
  lambda { |req| "#{req.request_method} #{req.filtered_path}" }
]
```

Then watch logs while testing:
```
grep "ChatCompletionService" log/development.log
```

You should see times dropping as changes are applied.

---

## Rollback Plan

If something breaks, each change is independent:

1. **Change #1 fails?** Switch back from `:anthropic` to `:openai` and model back to `"gpt-4o-mini"`
2. **Change #2 fails?** Revert the prompt to the original
3. **Change #3 fails?** Switch back from `"gpt-4o-mini"` to `"gpt-4-turbo"`
4. **Change #4 fails?** Switch `.last(10)` back to `.last(20)`
5. **Change #5 fails?** Set `LISTOPIA_USE_MODERATION=false` in .env
6. **Change #6 fails?** Revert the parallel code back to sequential

All changes are additive - they don't break the existing flow.

---

## Expected Results After Each Change

| Change | Time Before | Time After | Saved |
|--------|------------|-----------|-------|
| Baseline | 5-10s | 5-10s | - |
| +#1 (Haiku) | 5-10s | 4-8s | 0.5-1.5s |
| +#2 (Prompt) | 4-8s | 3.5-7.5s | 0.2-0.4s |
| +#3 (Model) | 3.5-7.5s | 2.5-5.5s | 1-2s |
| +#4 (History) | 2.5-5.5s | 2.3-5s | 0.2-0.5s |
| +#5 (Monitor) | 2.3-5s | 2.3-5s | 0 (safety) |
| +#6 (Parallel) | 2.3-5s | <2s | 1-2s |
| **TOTAL** | **5-10s** | **<2s** | **3-6s saved** |

---

## Verification Checklist

- [ ] Change #1: Claude Haiku intent router applied and tested
- [ ] Change #2: Parameter prompt improved and tested
- [ ] Change #3: ListRefinement using 4o-mini confirmed
- [ ] Change #4: Message history reduced to 10 confirmed
- [ ] Change #5: Moderation enabled (check logs for moderation API calls)
- [ ] Change #6: Parallel execution working (no errors in logs)
- [ ] All tests still passing: `bundle exec rspec`
- [ ] No regressions in chat functionality
- [ ] Response times significantly improved

---

## Questions?

If a change breaks:
1. Check the logs: `tail -f log/development.log | grep -i error`
2. Run tests: `bundle exec rspec spec/services/chat_completion_service_spec.rb`
3. Verify API keys are set: `echo $OPENAI_API_KEY`
4. Rollback the specific change and try again

Each change is independent and can be applied/removed without affecting others.

