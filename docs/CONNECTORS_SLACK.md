# Slack Connector Implementation

## Overview

The Slack connector enables one-way message posting from Listopia to Slack channels. Users can automatically notify Slack channels when items are created or completed, with rich message formatting and channel selection.

## Architecture

### Components

#### 1. **Slack Connector** (`app/connectors/slack.rb`)
- Manifest defining connector metadata
- OAuth scopes for messaging and channel access
- Settings schema (default channel, post on events)
- Operations: test_connection, pull (skipped), push

#### 2. **OAuth Service** (`app/services/connectors/slack/oauth_service.rb`)
- Slack OAuth 2.0 implementation (variant)
- Authorization URL generation with user scope
- Code exchange for bot access tokens
- Workspace info fetching from auth.test API
- No refresh tokens (Slack bot tokens don't expire)

#### 3. **Message Service** (`app/services/connectors/slack/message_service.rb`)
- Post messages to Slack channels
- Fetch workspace channels (public and private)
- Rich message blocks support (for formatted content)
- Sync logging for audit trail

#### 4. **Webhook Service** (`app/services/connectors/slack/webhook_service.rb`)
- Verify Slack request signatures (constant-time comparison)
- Handle Slack URL verification challenge
- Event dispatcher (message, reaction_added, app_mention)
- Secure signature verification to prevent timing attacks

#### 5. **Notify Job** (`app/jobs/connectors/messaging/slack/notify_job.rb`)
- Background job for posting item updates
- Triggered by item created/completed events
- Event-based posting (post_on_creation, post_on_completion settings)
- Current context setup for authorization

#### 6. **Controller** (`app/controllers/connectors/messaging/slack/channels_controller.rb`)
- ChannelsController: Select default channel for posting

## Setup & Configuration

### 1. Slack App Setup

```bash
# Create Slack App at https://api.slack.com/apps
# Navigate to "OAuth & Permissions"
# Add scopes:
#   - chat:write (post messages)
#   - channels:read (list channels)
#   - users:read (get user info)

# Install app to workspace
# Authorized Redirect URIs: https://yourdomain.com/connectors/oauth/slack/callback
# Request URL for events: https://yourdomain.com/connectors/messaging/slack/webhooks
```

### 2. Store Credentials

```yaml
# config/credentials.yml.enc
slack:
  client_id: "123456789.123456789"
  client_secret: "abc123xyz789abc123xyz789"
  signing_secret: "abc123xyz789abc123xyz789abc123xy"
```

Or use environment variables:
```bash
SLACK_CLIENT_ID=123456789.123456789
SLACK_CLIENT_SECRET=abc123xyz789abc123xyz789
SLACK_SIGNING_SECRET=abc123xyz789abc123xyz789abc123xy
```

### 3. Enable Event Subscriptions

```
# In Slack App settings:
# 1. Go to "Event Subscriptions"
# 2. Enable Events
# 3. Set Request URL: https://yourdomain.com/connectors/messaging/slack/webhooks
# 4. Slack will POST a challenge, handle in WebhookService#handle_verification
# 5. Subscribe to bot events:
#    - message.channels
#    - reaction_added
#    - app_mention
```

## OAuth Flow

### Authorization

```
1. User clicks "Connect Slack"
   ↓
2. App generates state token, stores in session
   ↓
3. Redirect to Slack OAuth URL with state parameter
   ↓
4. User authenticates to Slack and approves scopes
   ↓
5. Slack redirects back with authorization code + state
   ↓
6. App validates state (CSRF protection)
   ↓
7. Exchange code for bot token (access_token, no refresh_token)
   ↓
8. Decrypt and store tokens in connector_accounts
   ↓
9. Fetch workspace info from auth.test API
   ↓
10. User selects default channel for posting
```

### Token Lifecycle

Slack bot tokens do **not expire**. Unlike Google, there's no refresh token flow:

```
1. Store access_token in connector_accounts
2. Token remains valid indefinitely
3. If token is revoked, app will receive 401 errors
4. No automatic refresh needed
5. Manual revocation: user uninstalls app or removes token
```

## Message Posting

### Push Messages (Listopia → Slack)

```
1. Item created/completed event triggers NotifyJob
   ↓
2. Check if notification enabled for event_type:
   - "created" → check post_on_creation setting
   - "completed" → check post_on_completion setting
   ↓
3. Fetch default_channel_id from settings
   ↓
4. Build message text with emoji:
   - ✨ for created items
   - ✅ for completed items
   - 📌 for other events
   ↓
5. Build rich message blocks with title and description
   ↓
6. POST to Slack chat.postMessage API
   ↓
7. Log operation with timestamp
```

### Message Format

**Text Format (fallback):**
```
✅ *Task Title*
List: Example List
```

**Rich Blocks Format:**
```json
[
  {
    "type": "section",
    "text": {
      "type": "mrkdwn",
      "text": "*Task Title*\nTask description here"
    }
  },
  {
    "type": "context",
    "elements": [
      {
        "type": "mrkdwn",
        "text": "📋 From Listopia"
      }
    ]
  }
]
```

## Webhook Handling

### Request Verification

All webhook requests from Slack include a signature in the `X-Slack-Request-Timestamp` and `X-Slack-Signature` headers:

```ruby
# Slack signature format: v0=<HMAC-SHA256>
base_string = "v0:#{timestamp}:#{body}"
computed_sig = "v0=#{HMAC-SHA256(signing_secret, base_string)}"
secure_compare(computed_sig, slack_signature)
```

**Security:** Uses constant-time comparison to prevent timing attacks.

### Supported Events

1. **URL Verification Challenge**
   - Slack sends challenge when webhook endpoint is registered
   - Return `{ challenge: "..." }` to confirm

2. **Message Events**
   - Messages posted to channels monitoring the app
   - Can trigger custom actions (future enhancement)

3. **Reaction Added**
   - User reacts to message with emoji
   - Can trigger item updates (future enhancement)

4. **App Mention**
   - User mentions the app in a message
   - Can handle commands (future enhancement)

## Settings Schema

### default_channel_id
- **Type:** Select
- **Options:** Fetched from Slack workspace channels
- **Purpose:** Default channel for posting item updates
- **Required:** Yes

### post_on_completion
- **Type:** Boolean
- **Default:** `true`
- **Purpose:** Post to Slack when items are completed

### post_on_creation
- **Type:** Boolean
- **Default:** `false`
- **Purpose:** Post to Slack when new items are created

## Error Handling

### Token Errors
```
- Missing token → Account shows as :revoked
- Invalid scopes → 403 Forbidden from Slack API
- App uninstalled → 401 Unauthorized, mark as :errored
```

### API Errors
```
- 404 channel_not_found → Channel deleted or no access
- 403 not_in_channel → Bot not in channel, add manually
- 429 rate_limited → Slack rate limit hit, retry with backoff
- 500 server_error → Slack API error, retry later
```

### Webhook Errors
```
- Invalid signature → Request rejected, check signing_secret
- Old timestamp → Request ignored (>5 min old), prevent replay attacks
- Duplicate message_ts → Idempotent, check timestamp
```

## Monitoring & Debugging

### Sync Logs

```ruby
# View message posting history
connector_account.sync_logs.where(operation: "post_message").recent.limit(10)

# Check for failures
connector_account.sync_logs.where(status: "failure")

# Measure performance
log = connector_account.sync_logs.recent.first
duration_seconds = log.duration_ms / 1000.0
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "channel_not_found" | Channel ID invalid or deleted | Re-select channel in settings |
| "not_in_channel" | Bot not member of channel | Add bot manually in Slack |
| "invalid_token" | Token revoked or invalid | Disconnect and reconnect |
| "token_revoked" | User uninstalled app | Reconnect via OAuth |
| "not_authed" | Missing credentials | Check SLACK_CLIENT_ID/SECRET |
| No messages posted | Settings not configured | Set default_channel_id and post_on_* |

## Testing

### Unit Tests
```bash
bundle exec rspec spec/services/connectors/slack/oauth_service_spec.rb
bundle exec rspec spec/services/connectors/slack/message_service_spec.rb
bundle exec rspec spec/services/connectors/slack/webhook_service_spec.rb
bundle exec rspec spec/connectors/slack_spec.rb
```

### Integration Tests
```bash
bundle exec rspec spec/integration/connectors/slack_spec.rb
```

### Manual Testing

```ruby
# Create test account
user = User.find(1)
org = user.organizations.first

account = Connectors::Account.create!(
  user: user,
  organization: org,
  provider: "slack",
  provider_uid: "T123456789",
  access_token: "xoxb-test-token",
  status: "active"
)

# Test channel fetch
service = Connectors::Slack::MessageService.new(connector_account: account)
channels = service.fetch_channels

# Test message posting
result = service.post_message("C123456", "Test message")

# Set default channel
account.settings.create!(key: "default_channel_id", value: "C123456")

# Test notify job
Connectors::Messaging::Slack::NotifyJob.perform_later(
  event_type: "created",
  item_id: item.id,
  connector_account_id: account.id
)
```

## Rate Limiting

Slack API has these quotas:
- 1 message per second per channel (soft limit)
- 60 requests per minute per token
- WebSocket rate limits for real-time messaging

To avoid hitting limits:
- Batch notifications (collect multiple updates into one message)
- Queue jobs to spread posting over time
- Implement exponential backoff for rate limit errors
- Monitor usage in Slack app settings

## Security Considerations

1. **Token Storage:** Bot tokens are encrypted at rest using Rails 8.1 encryption
2. **Signature Verification:** All webhook requests verified using HMAC-SHA256 with constant-time comparison
3. **CSRF Protection:** OAuth state parameter validated on callback
4. **Timestamp Validation:** Webhook timestamps checked to be within 5 minutes (prevent replay attacks)
5. **Scope Minimization:** Only request scopes needed for posting and channel access

## Future Enhancements

1. **Webhook Events:** React to Slack reactions and mentions to update items
2. **Interactive Messages:** Add buttons/forms to messages for task management in Slack
3. **Threading:** Post follow-ups in threads to reduce channel noise
4. **Rich Attachments:** Include images, links, and metadata
5. **Multiple Channels:** Post different event types to different channels
6. **Slash Commands:** Implement `/create-list` command in Slack
7. **App Home:** Custom app home with quick actions
8. **User Mentions:** Mention assignees when items are assigned in Slack

## Related Documentation

- `CONNECTORS_OAUTH.md` - OAuth 2.0 implementation details
- `CONNECTORS_SECURITY.md` - Token encryption and authorization
- `CONNECTORS_ARCHITECTURE_PLAN.md` - Overall connector architecture
