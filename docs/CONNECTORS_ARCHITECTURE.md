# Connectors Architecture - Complete Implementation

## Overview

Listopia Connectors is a production-ready framework for integrating third-party services (Google Calendar, Microsoft Outlook, Slack, Google Drive) with built-in OAuth support, real-time sync, and extensible architecture for future connector gems.

**Design Goal:** Clean isolation of concerns supporting gem extraction without core application changes.

**Status:** ✅ **All 6 phases complete** - Google Calendar, Microsoft Outlook, Slack, Google Drive implemented and tested.

---

## Implementation Summary

### Phases Completed

| Phase | Connector | Type | Status | Features |
|-------|-----------|------|--------|----------|
| 1 | Foundation | Base | ✅ | Models, migrations, base classes, policies |
| 2 | OAuth Infrastructure | Base | ✅ | Generic OAuth, state validation, token refresh |
| 3 | Google Calendar | Integration | ✅ | Bidirectional sync, timezone, conflict detection |
| 4 | Microsoft Outlook | Integration | ✅ | PKCE flow, equivalent features |
| 5 | Slack | Messaging | ✅ | One-way posting, webhooks, notifications |
| 6 | Google Drive | Storage | ✅ | Read-only browsing, search, pagination |

### Code Metrics

- **Total Lines:** ~10,000+
- **Connectors:** 6 implementations
- **Services:** 12 provider services
- **Controllers:** 8 endpoints
- **Tests:** 20+ specs
- **Documentation:** 2,000+ lines

---

## Directory Structure

```
lib/connectors/                          # Self-registering connectors
├── base_connector.rb                    # Abstract base class + DSL
├── registry.rb                          # Self-registration system
├── stub.rb                              # Test provider
├── google_calendar.rb
├── microsoft_outlook.rb
├── google_drive.rb
└── slack.rb

app/
├── models/connectors/
│   ├── account.rb                       # OAuth accounts (encrypted tokens)
│   ├── setting.rb                       # Schema-driven settings
│   ├── sync_log.rb                      # Audit trail
│   └── event_mapping.rb                 # External ↔ local ID mapping
│
├── services/connectors/
│   ├── base_service.rb                  # Sync logging + token refresh
│   ├── oauth_service.rb                 # Token exchange/refresh
│   ├── sync_service.rb                  # Bidirectional sync pattern
│   ├── google/
│   │   ├── oauth_service.rb
│   │   ├── calendar_fetch_service.rb
│   │   ├── event_sync_service.rb
│   │   └── file_service.rb
│   ├── microsoft/
│   │   ├── oauth_service.rb
│   │   ├── calendar_fetch_service.rb
│   │   └── event_sync_service.rb
│   ├── messaging/slack/
│   │   ├── oauth_service.rb
│   │   ├── message_service.rb
│   │   └── webhook_service.rb
│   └── stub/
│       └── oauth_service.rb
│
├── controllers/connectors/
│   ├── base_controller.rb               # Auth + context
│   ├── connector_accounts_controller.rb # Account management
│   ├── oauth_controller.rb              # OAuth flow
│   ├── settings_controller.rb           # Generic settings CRUD
│   ├── calendars/
│   │   ├── google/calendars_controller.rb
│   │   ├── google/events_controller.rb
│   │   ├── microsoft/calendars_controller.rb
│   │   └── microsoft/events_controller.rb
│   ├── messaging/slack/
│   │   ├── channels_controller.rb
│   │   └── webhooks_controller.rb
│   └── storage/google_drive/
│       └── files_controller.rb
│
├── jobs/connectors/
│   ├── base_job.rb                      # Error handling + context
│   ├── token_refresh_job.rb             # Proactive refresh
│   ├── calendars/google/sync_job.rb
│   ├── calendars/microsoft/sync_job.rb
│   └── messaging/slack/notify_job.rb
│
├── policies/connectors/
│   └── account_policy.rb                # User-scoped access
│
└── views/connectors/
    ├── connector_accounts/              # Catalog + connected accounts
    ├── settings/                        # Generic schema-driven forms
    ├── oauth/                           # Success/failure pages
    ├── calendars/
    │   ├── google/calendars/
    │   ├── google/events/
    │   ├── microsoft/calendars/
    │   └── microsoft/events/
    ├── messaging/slack/channels/
    └── storage/google_drive/files/

config/
├── initializers/connectors.rb           # Connector loading
└── routes.rb                            # Connector namespaces
```

---

## Database Schema

### connector_accounts
```sql
id uuid pk, user_id uuid fk, organization_id uuid fk,
provider varchar (google_calendar|microsoft_outlook|slack|google_drive),
provider_uid varchar,
display_name varchar, email varchar,
access_token_encrypted text, refresh_token_encrypted text,
token_expires_at timestamptz, token_scope varchar,
status varchar (active|paused|revoked|errored),
last_sync_at timestamptz, last_error text, error_count integer,
metadata jsonb,
UNIQUE (user_id, provider, provider_uid)
```

### connector_settings
```sql
id uuid pk, connector_account_id uuid fk,
key varchar, value text,
UNIQUE (connector_account_id, key)
```

### connector_sync_logs
```sql
id uuid pk, connector_account_id uuid fk,
operation varchar, status varchar,
records_processed/created/updated/failed integer,
error_message text, duration_ms integer,
started_at timestamptz, completed_at timestamptz
```

### connector_event_mappings
```sql
id uuid pk, connector_account_id uuid fk,
external_id varchar, external_type varchar,
local_type varchar, local_id uuid,
sync_direction varchar, last_synced_at timestamptz,
external_etag varchar, metadata jsonb,
UNIQUE (connector_account_id, external_id, external_type)
```

---

## Key Architectural Patterns

### 1. Self-Registering Connectors

```ruby
# lib/connectors/google_calendar.rb
module Connectors
  class GoogleCalendar < BaseConnector
    connector_key "google_calendar"
    connector_name "Google Calendar"
    connector_category "calendars"
    # ... implementation
  end
end

# Auto-registers when loaded
Connectors::Registry.register(Connectors::GoogleCalendar)
```

### 2. Multi-Layer Authorization

```
Request → Controller (authenticate_user!)
        → Service (Current.user + account ownership)
        → Connector (final check)
        → Job (data integrity for background work)
```

### 3. Token Encryption at Rest

```ruby
account.access_token = "plaintext"
account.save!
# Stored encrypted in database as access_token_encrypted

account.reload
account.access_token  # Decrypts and returns plaintext
```

### 4. Sync Logging with Audit Trail

```ruby
service.with_sync_log(operation: "fetch_calendars") do |log|
  result = fetch_calendars
  log.update!(records_processed: result.count)
  result
end
# Automatically creates audit entry with timing
```

### 5. Schema-Driven Settings

```ruby
class GoogleCalendar < BaseConnector
  settings_schema(
    default_calendar_id: { type: :select, options: [...] },
    sync_direction: { type: :select, options: ["pull", "push", "both"] },
    auto_sync: { type: :boolean, default: true }
  )
end

# Settings form auto-generated from schema
```

### 6. OAuth State Parameter CSRF Protection

```ruby
# authorize action
state = SecureRandom.hex(32)
session[:oauth_state] = state
redirect_to google_oauth_url(state: state)

# callback action
if session[:oauth_state] != params[:state]
  raise "CSRF attack detected"
end
```

---

## Security Implementation

### Encryption
- **Algorithm:** AES-256-GCM via `ActiveSupport::MessageEncryptor`
- **Key Management:** 32-byte key from `credentials.yml.enc`
- **Scope:** Access tokens and refresh tokens encrypted at rest

### Authorization Layers
1. **Controller:** Rails `authenticate_user!` + session validation
2. **Service:** Current context + account ownership check
3. **Connector:** Ownership verification + initialization
4. **Job:** Account/user/organization existence validation

### CSRF Protection
- OAuth state parameter validated on callback
- State stored in secure session (HTTP-only, same-site)
- Invalid/missing state triggers error

### Audit Trail
- All operations logged in `connector_sync_logs`
- Cannot be modified/deleted (append-only)
- Includes timing, operation type, record counts, errors

### Error Handling
- Failed operations set `status: :errored`
- Error message stored for debugging
- Error count tracked for monitoring
- Graceful degradation (no token leaks in errors)

**See:** `CONNECTORS_SECURITY.md` and `CONNECTORS_SECURITY_CHECKLIST.md`

---

## OAuth Implementations

### Google Calendar & Google Drive
- **Type:** OAuth 2.0 standard flow
- **Scopes:** Calendar/Drive specific
- **Refresh:** Automatic via `TokenRefreshJob`
- **Key Difference:** Drive is read-only; Calendar is bidirectional

### Microsoft Outlook
- **Type:** OAuth 2.0 with PKCE
- **Scopes:** Outlook-specific (equivalent to Google)
- **Refresh:** Automatic via `TokenRefreshJob`
- **Key Feature:** Code verifier/challenge for native app security

### Slack
- **Type:** OAuth 2.0 variant (different flow)
- **Scopes:** Message posting + channel browsing
- **Refresh:** Not needed (Slack bot tokens don't expire)
- **Webhook:** Event-based, signature-verified

---

## Connector Features

### Google Calendar ✅
- **Sync Direction:** Bidirectional (pull/push)
- **Features:** Event fetch, create, update; timezone handling
- **Conflict Detection:** ETag-based
- **Special:** Recurring events, attendee invites

### Microsoft Outlook ✅
- **Sync Direction:** Bidirectional (pull/push)
- **Features:** Event fetch, create, update; timezone handling
- **Conflict Detection:** changeKey-based
- **Special:** Recurring events, organizer info

### Slack ✅
- **Sync Direction:** One-way (push only)
- **Features:** Message posting, channel browsing, webhooks
- **Events:** Message, reaction_added, app_mention
- **Special:** Signature verification, rich blocks

### Google Drive ✅
- **Sync Direction:** Read-only (browse only)
- **Features:** File listing, search, pagination, metadata
- **Metadata:** Size, type, modified date, owner, webViewLink
- **Special:** Support for different export formats

---

## API Operations

### Common Operations

```ruby
# Test connection
connector.test_connection
# Returns: { status, message, metadata }

# Pull (sync to Listopia)
connector.pull
# Returns: { status, records_pulled, data }

# Push (sync to provider)
connector.push(data)
# Returns: { status, records_pushed, data }
```

### Provider-Specific

```ruby
# Google Calendar
service = Connectors::Google::CalendarFetchService.new(connector_account: account)
calendars = service.fetch_calendars
events = service.fetch_events

# Google Drive
service = Connectors::Google::FileService.new(connector_account: account)
files = service.list_files(query: "report")
file = service.get_file(file_id)

# Slack
service = Connectors::Messaging::Slack::MessageService.new(connector_account: account)
result = service.post_message(channel_id, text)
channels = service.fetch_channels

# Webhooks (Slack)
service.verify_request(timestamp, signature, body)
service.handle_event(event_payload)
```

---

## Testing

### Unit Tests
```bash
bundle exec rspec spec/connectors/
bundle exec rspec spec/services/connectors/
bundle exec rspec spec/controllers/connectors/
bundle exec rspec spec/models/connectors/
```

### Integration Tests
```bash
bundle exec rspec spec/integration/connectors/
```

### Security Verification
```bash
# See CONNECTORS_SECURITY_CHECKLIST.md
```

---

## Routes

```ruby
namespace :connectors do
  # Account management
  resources :connector_accounts, only: [:index, :destroy] do
    member { patch :pause; patch :resume; post :test }
    collection { get :available }
  end

  # Settings (generic)
  resources :settings, only: [:show, :update], param: :connector_account_id

  # OAuth flow
  scope :oauth, controller: "oauth" do
    get ":provider/authorize", action: :authorize
    get ":provider/callback", action: :callback
  end

  # Calendar connectors
  namespace :calendars do
    namespace :google do
      resources :calendars, only: [:index] do
        collection { post :select }
      end
      resources :events, only: [:index] do
        collection { post :sync }
      end
    end
    namespace :microsoft do
      # Same structure
    end
  end

  # Storage connectors
  namespace :storage do
    namespace :google_drive do
      resources :files, only: [:index, :show]
    end
  end

  # Messaging connectors
  namespace :messaging do
    namespace :slack do
      resources :channels, only: [:index] do
        collection { post :select }
      end
      post "webhooks", to: "webhooks#receive"
    end
  end
end
```

---

## Future Enhancements

### Phase 7: Bidirectional Slack
- Incoming webhook events → list item creation
- Slack reactions → item status changes
- Threading support

### Phase 8: Google Drive Attachments
- File attachment to list items
- Preview generation
- Version history

### Phase 9: Advanced Features
- Folder syncing
- Watch/subscription API
- Incremental sync
- Batch operations

### Phase 10: Gem Extraction
- Extract individual connectors as gems
- Shared connector infrastructure gem
- Plugin system for custom connectors

---

## Deployment

### Production Setup

```bash
# 1. Generate encryption key
openssl rand -hex 32

# 2. Add to encrypted credentials
EDITOR=nano rails credentials:edit
# connector_tokens:
#   secret: "..."

# 3. Set provider credentials
# google_calendar:
#   client_id: "..."
#   client_secret: "..."

# 4. Run migrations
rails db:migrate

# 5. Test encryption
rails c
Connectors::Account.first&.access_token  # Should decrypt
```

### Environment Variables (Optional)
```bash
# OAuth provider credentials (alternative to credentials.yml.enc)
GOOGLE_CLIENT_ID="..."
GOOGLE_CLIENT_SECRET="..."
SLACK_CLIENT_ID="..."
SLACK_CLIENT_SECRET="..."
SLACK_SIGNING_SECRET="..."
```

---

## Monitoring

### Key Metrics
- `Connectors::SyncLog` - operation counts, success/failure rates
- `Connectors::Account.where(status: :errored)` - error tracking
- `error_count` - cumulative errors per account

### Alerts (Recommended)
- Account status changes to `:errored`
- Repeated sync failures
- Unusual error patterns

### Logs
```bash
# Monitor sync operations
tail -f log/production.log | grep "Connectors"

# Check error counts
rails c
Connectors::Account.where("error_count > 5")
```

---

## Related Documentation

- **[CONNECTORS_SECURITY.md](CONNECTORS_SECURITY.md)** - Detailed security model
- **[CONNECTORS_SECURITY_CHECKLIST.md](CONNECTORS_SECURITY_CHECKLIST.md)** - Pre-testing security verification
- **[CONNECTORS_OAUTH.md](CONNECTORS_OAUTH.md)** - OAuth 2.0 implementation
- **[CONNECTORS_GOOGLE_CALENDAR.md](CONNECTORS_GOOGLE_CALENDAR.md)** - Google Calendar specifics
- **[CONNECTORS_MICROSOFT_OUTLOOK.md](CONNECTORS_MICROSOFT_OUTLOOK.md)** - Microsoft specifics
- **[CONNECTORS_SLACK.md](CONNECTORS_SLACK.md)** - Slack specifics
- **[CONNECTORS_GOOGLE_DRIVE.md](CONNECTORS_GOOGLE_DRIVE.md)** - Google Drive specifics
