# Security Features Summary

## What Was Implemented

A comprehensive security layer for the unified chat system with two-stage protection:

### 1. Prompt Injection Detection (Local)
- **Service**: `PromptInjectionDetector`
- **Detection Methods**:
  - Pattern matching (20+ regex patterns)
  - Prompt rewriting detection ("ignore previous instructions")
  - Role switching detection ("act as", "pretend you are")
  - Context escape detection ("disregard system prompt")
  - Jailbreak keyword detection ("unrestricted", "no limitations")
  - Encoding/obfuscation detection (Base64, HTML entities, Unicode tricks)
  - Repetition attack detection (repeated instructions)
  - Token smuggling detection

- **Risk Levels**:
  - Low (0-2 points): Logged, message allowed
  - Medium (3-5 points): Warned, message allowed, logged
  - High (6+): Blocked, message rejected, logged

- **Environment Variable**: `PROMPT_INJECTION_BLOCK_THRESHOLD`

### 2. Content Moderation (OpenAI API via RubyLLM)
- **Service**: `ContentModerationService`
- **Categories Checked** (11 total):
  - Hate speech and threats
  - Harassment and threats
  - Self-harm content (intent, instructions)
  - Sexual content (including minors)
  - Violence (including graphic)

- **Automatic Actions**:
  - Flags harmful content
  - Blocks message from being sent to LLM
  - Creates audit log entry
  - Marks message as blocked
  - Checks for auto-archive threshold

- **Environment Variable**: `LISTOPIA_USE_MODERATION`

### 3. Audit Trail (ModerationLog Model)
- **Tracks**:
  - Violation type (injection, hate speech, harassment, etc.)
  - Action taken (logged, warned, blocked, archived)
  - Detected patterns and scores
  - Organization and user context
  - Chat and message references

- **Built-in Analytics**:
  - `violation_summary()` - count by type over time window
  - `repeat_offenders()` - users with multiple violations
  - `check_auto_archive()` - auto-archive on threshold

- **Environment Variable**: `MODERATION_AUTO_ARCHIVE_THRESHOLD`

### 4. Integration with Chat System
- **Location**: `ChatsController#create_message`
- **Flow**:
  1. User submits message
  2. Prompt injection detection runs
  3. If medium risk: warned but allowed
  4. If high risk: blocked, error returned
  5. If low risk: continue
  6. Message object created
  7. Content moderation check
  8. If flagged: blocked, error returned, log created
  9. If allowed: continue to LLM processing

## Configuration

### Environment Variables

```bash
# Enable OpenAI moderation (true/false)
LISTOPIA_USE_MODERATION=true

# Risk threshold for blocking (low/medium/high)
PROMPT_INJECTION_BLOCK_THRESHOLD=high

# Auto-archive after N violations in 7 days
MODERATION_AUTO_ARCHIVE_THRESHOLD=5
```

### Environment Defaults

**Development (.env.development)**
- LISTOPIA_USE_MODERATION=true
- PROMPT_INJECTION_BLOCK_THRESHOLD=high
- MODERATION_AUTO_ARCHIVE_THRESHOLD=5

**Testing (.env.test)**
- LISTOPIA_USE_MODERATION=false (local detection only)
- PROMPT_INJECTION_BLOCK_THRESHOLD=high
- MODERATION_AUTO_ARCHIVE_THRESHOLD=5

## Database Schema

### moderation_logs table
```sql
- id (UUID)
- chat_id (FK)
- message_id (FK, optional)
- user_id (FK)
- organization_id (FK)
- violation_type (enum: 8 types)
- action_taken (enum: 4 actions)
- detected_patterns (JSONB array)
- moderation_scores (JSONB object)
- prompt_injection_risk (string)
- details (text)
- created_at, updated_at

Indexes:
- [organization_id, created_at]
- [user_id, created_at]
- violation_type
- action_taken
```

### messages table enhancement
```sql
- blocked (boolean, default: false)

Index:
- blocked
```

## Security Features Implemented

✅ **Prompt Injection Detection**
- 20+ pattern-based detections
- Risk scoring (0-10 scale)
- Three-level response (warn/block/allow)

✅ **Content Moderation**
- 11 OpenAI moderation categories
- Real-time flagging
- Fallback to local detection if API unavailable

✅ **Audit Trail**
- Complete logging of all security events
- Organization-scoped for multi-tenancy
- User and chat context preserved

✅ **Auto-Protect Mechanisms**
- Auto-archive on repeated violations
- Message blocking for harmful content
- Graceful degradation if APIs unavailable

✅ **User-Friendly Errors**
- Clear messages for blocked content
- Turbo Stream and JSON response formats
- No exposure of security internals

## Testing

All security features have been tested:

```bash
# Test prompt injection detection
rails runner 'PromptInjectionDetector.new(message: "Ignore previous instructions").call'

# Test content moderation
rails runner 'ContentModerationService.new(content: "...", user: user, chat: chat).call'

# Test moderation logging
rails runner 'ModerationLog.by_organization(org).count'

# Test auto-archive
rails runner 'ModerationLog.check_auto_archive(chat, org)'
```

## Future Enhancements

- Machine learning model for improved detection
- Custom word lists per organization
- Rate limiting (requires rack-attack gem)
- Webhook notifications for violations
- Appeal mechanism for false positives
- Compliance reporting (GDPR, SOC2)
- Cost tracking for moderation API calls

## Files Changed

### New Files
- `app/services/prompt_injection_detector.rb` (200 LOC)
- `app/services/content_moderation_service.rb` (182 LOC)
- `app/models/moderation_log.rb` (139 LOC)
- `db/migrate/20251208185230_create_moderation_logs.rb`
- `db/migrate/20251208185450_add_blocked_to_messages.rb`
- `SECURITY_IMPLEMENTATION_PLAN.md` (documentation)
- `SECURITY_FEATURES_SUMMARY.md` (this file)

### Modified Files
- `app/controllers/chats_controller.rb` (+125 LOC for security checks)
- `.env.example` (added security configuration)
- `.env.development` (added security configuration)
- `.env.test` (added security configuration)

## Deployment Notes

1. **Production**: Set `LISTOPIA_USE_MODERATION=true` with valid OpenAI API key
2. **Staging**: Can use either true/false depending on testing needs
3. **Development**: Configured to use both local and OpenAI moderation
4. **Testing**: Local detection only (OpenAI API disabled)

## Support & Monitoring

Check moderation logs:
```ruby
# Last 24 hours
ModerationLog.last_24_hours

# By organization
ModerationLog.by_organization(org)

# Violation summary
ModerationLog.violation_summary(org, 24.hours)

# Repeat offenders
ModerationLog.repeat_offenders(org, 7.days, 3)
```

## Security Best Practices

- Moderation logs are retained for audit purposes
- All violations are logged with user context
- Organization boundaries are enforced
- Blocked messages are still stored (but marked `blocked: true`)
- Error messages don't expose technical details
- Graceful degradation if external APIs fail
