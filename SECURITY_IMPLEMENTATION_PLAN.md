# Security Implementation Plan - Prompt Injection Detection & Moderation

## Overview

Implement comprehensive security features for the unified chat system:
1. **Prompt Injection Detection** - Detect malicious prompts attempting to manipulate LLM
2. **Content Moderation** - Leverage RubyLLM's OpenAI moderation API
3. **Moderation Logs** - Audit trail of moderation actions
4. **Abuse Detection** - Track patterns of harmful behavior

## Architecture

### 1. PromptInjectionDetector Service

**Location:** `app/services/prompt_injection_detector.rb`

Implements multiple detection strategies:

```ruby
class PromptInjectionDetector
  # Strategy patterns
  INJECTION_PATTERNS = [
    # Prompt rewriting attempts
    /ignore previous instructions/i,
    /forget everything/i,
    /start over/i,

    # Role switching
    /you are now/i,
    /act as/i,
    /pretend you are/i,

    # Context escape attempts
    /outside the system/i,
    /disregard the system prompt/i,
    /bypass the guidelines/i,

    # Jailbreak keywords
    /unrestricted/i,
    /without limitations/i,
    /anything goes/i,
  ]

  SUSPICIOUS_PATTERNS = [
    # Multi-language encoding
    /\p{Cyrillic}/,  # Cyrillic alphabet often used for obfuscation
    /&#\d{4,5};/,    # HTML entities
    /&#x[0-9a-f]+;/i, # Hex entities

    # Base64 encoded content
    /^[A-Za-z0-9+\/]{20,}={0,2}$/,
  ]

  def initialize(message:, context: nil)
    @message = message
    @context = context
  end

  def call
    # Returns { detected: true/false, risk_level: "low"/"medium"/"high", patterns: [] }
  end

  private

  def check_injection_patterns
    # Matches against INJECTION_PATTERNS
  end

  def check_suspicious_patterns
    # Matches against SUSPICIOUS_PATTERNS
  end

  def check_prompt_confusion
    # Detects prompt vs data confusion (prompt injection meta-attack)
  end

  def check_token_smuggling
    # Detects attempts to smuggle control tokens or special sequences
  end
end
```

### 2. ContentModerationService

**Location:** `app/services/content_moderation_service.rb`

Wraps RubyLLM's OpenAI moderation:

```ruby
class ContentModerationService
  # Moderation categories per OpenAI API
  CATEGORIES = [
    :hate,           # Hateful content
    :hate_threatening,
    :harassment,     # Harassing content
    :harassment_threatening,
    :self_harm,      # Self-harm content
    :self_harm_intent,
    :self_harm_instructions,
    :sexual,         # Sexual content
    :sexual_minors,  # Sexual content involving minors
    :violence,       # Violent content
    :violence_graphic, # Graphic violence
  ]

  def initialize(content:, user: nil, chat: nil)
    @content = content
    @user = user
    @chat = chat
  end

  def call
    # Returns moderation result with:
    # - flagged: true/false
    # - categories: { category => true/false }
    # - scores: { category => 0.0..1.0 }
  end

  private

  def call_openai_moderation
    # Uses RubyLLM::Moderation.create(text: @content)
  end

  def log_moderation_action(result)
    # Creates ModerationLog entry
  end
end
```

### 3. ModerationLog Model

**Location:** `app/models/moderation_log.rb`

Tracks all moderation actions:

```ruby
class ModerationLog < ApplicationRecord
  belongs_to :chat
  belongs_to :message, optional: true
  belongs_to :user
  belongs_to :organization

  enum :violation_type, {
    prompt_injection: 0,
    harmful_content: 1,
    hate_speech: 2,
    harassment: 3,
    self_harm: 4,
    sexual_content: 5,
    violence: 6,
    other: 7
  }

  enum :action_taken, {
    logged: 0,        # Just logged, allowed
    warned: 1,        # Warned user
    blocked: 2,       # Message blocked
    archived: 3       # Chat archived
  }

  # Columns
  # - id: uuid
  # - chat_id: uuid (FK)
  # - message_id: uuid (FK, optional - injection detected before message created)
  # - user_id: uuid (FK)
  # - organization_id: uuid (FK)
  # - violation_type: int (enum)
  # - action_taken: int (enum)
  # - detected_patterns: jsonb (array of detected patterns)
  # - moderation_scores: jsonb (OpenAI moderation scores)
  # - prompt_injection_risk: string (low/medium/high)
  # - details: text (detailed explanation)
  # - created_at, updated_at
end
```

### 4. Integration with ChatsController

**Location:** `app/controllers/chats_controller.rb` - create_message action

```ruby
def create_message
  @chat = Chat.find(params[:chat_id])
  authorize @chat

  content = params.require(:message).permit(:content)[:content].to_s.strip

  # Step 1: Check for prompt injection
  injection_detector = PromptInjectionDetector.new(message: content, context: @chat.focused_resource)
  injection_result = injection_detector.call

  if injection_result[:detected] && injection_result[:risk_level] == "high"
    create_moderation_log(
      violation_type: :prompt_injection,
      action_taken: :blocked,
      detected_patterns: injection_result[:patterns],
      details: "High-risk prompt injection attempt detected"
    )
    return render_security_error("Suspicious input detected and blocked")
  end

  if injection_result[:detected]
    create_moderation_log(
      violation_type: :prompt_injection,
      action_taken: :warned,
      detected_patterns: injection_result[:patterns],
      details: "Medium-risk prompt injection attempt"
    )
  end

  # Step 2: Create user message
  @user_message = Message.create_user(chat: @chat, user: current_user, content: content)

  # Step 3: Check content moderation
  moderation_service = ContentModerationService.new(
    content: content,
    user: current_user,
    chat: @chat
  )
  moderation_result = moderation_service.call

  if moderation_result[:flagged]
    # Block harmful content
    @user_message.update(blocked: true)
    create_moderation_log(
      violation_type: categorize_violation(moderation_result),
      action_taken: :blocked,
      message: @user_message,
      moderation_scores: moderation_result[:scores],
      details: "Content flagged by OpenAI moderation"
    )
    return render_security_error("Content not allowed")
  end

  # Step 4: Process with LLM (normal flow)
  process_message(@chat, @user_message)
end

private

def create_moderation_log(violation_type:, action_taken:, **details)
  ModerationLog.create!(
    chat: @chat,
    user: current_user,
    organization: current_organization,
    violation_type: violation_type,
    action_taken: action_taken,
    **details
  )
end
```

## Implementation Details

### Security Flow Diagram

```
Message Input
  ↓
[1. Prompt Injection Detection]
  - Check regex patterns
  - Analyze for role switching
  - Detect jailbreak attempts
  ↓
  Detected? → Log Warning/Block based on risk level
  ↓
[2. Create Message Object]
  ↓
[3. Content Moderation (OpenAI)]
  - Call RubyLLM::Moderation
  - Get category scores
  ↓
  Flagged? → Block + Log → Return Error
  ↓
[4. Process with LLM]
  - Build context
  - Generate response
  - Log success
```

## Database Schema

### Migration: create_moderation_logs

```ruby
create_table :moderation_logs, id: :uuid do |t|
  t.references :chat, type: :uuid, foreign_key: true
  t.references :message, type: :uuid, foreign_key: true, optional: true
  t.references :user, type: :uuid, foreign_key: true
  t.references :organization, type: :uuid, foreign_key: true

  t.integer :violation_type, default: 0
  t.integer :action_taken, default: 0

  t.jsonb :detected_patterns, default: []
  t.jsonb :moderation_scores, default: {}
  t.string :prompt_injection_risk, default: "low"
  t.text :details

  t.timestamps
end

add_index :moderation_logs, [:organization_id, :created_at]
add_index :moderation_logs, [:user_id, :created_at]
add_index :moderation_logs, :violation_type
add_index :moderation_logs, :action_taken
```

## Testing Strategy

### Unit Tests

**PromptInjectionDetector:**
- Test each pattern type (injection, jailbreak, encoding, token smuggling)
- Test risk level calculation
- Test false positives/negatives with legitimate prompts

**ContentModerationService:**
- Mock OpenAI moderation API responses
- Test flagged content handling
- Test score parsing and categorization

### Integration Tests

**ChatsController#create_message:**
- Test prompt injection detection blocks high-risk input
- Test moderation log creation on violations
- Test normal message flow is unaffected
- Test error responses are user-friendly

## Monitoring & Reporting

Add to DashboardController or admin panel:

```ruby
class SecurityDashboard
  def violation_summary
    # Past 24 hours
    ModerationLog
      .where(created_at: 24.hours.ago..)
      .group(:violation_type)
      .count
  end

  def repeat_offenders
    # Users with 3+ violations in past 7 days
    ModerationLog
      .where(created_at: 7.days.ago..)
      .group(:user_id)
      .having("count(*) >= 3")
      .count
  end
end
```

## Configuration

### Environment Variables

```bash
# Enable/disable prompt injection detection
ENABLE_PROMPT_INJECTION_DETECTION=true

# Enable/disable content moderation
ENABLE_CONTENT_MODERATION=true

# Risk threshold for blocking (low/medium/high)
PROMPT_INJECTION_BLOCK_THRESHOLD=high

# Auto-archive chat after N violations
AUTO_ARCHIVE_AFTER_VIOLATIONS=5
```

## Rollout Strategy

1. **Phase 1**: Deploy with logging only (no blocking)
2. **Phase 2**: Enable warnings for medium-risk injections
3. **Phase 3**: Enable blocking for high-risk injections
4. **Phase 4**: Enable full moderation with auto-archiving

## Future Enhancements

- [ ] Machine learning model for detection
- [ ] Custom word lists per organization
- [ ] Rate limiting per user/organization
- [ ] Webhook notifications for violations
- [ ] Compliance reporting (GDPR, SOC2)
- [ ] Appeal mechanism for false positives
