# Connectors Namespace - Complete Architecture Plan

## Overview

Listopia Connectors is a structured framework for integrating third-party services (Google Calendar, Slack, etc.) with built-in OAuth support, real-time sync, and extensible architecture for connector gems.

**Design Goal:** Clean isolation of concerns so individual connectors can later be extracted as gems without modifying core application code.

---

## Scope Decisions

### User-Level Accounts
- Accounts are **user-scoped**, not organization-scoped
- Each user manages their own OAuth connections
- Organizations view user's public integrations but cannot access credentials
- Enables: Calendar invites use user's default calendar, not org's

### Settings & Views Strategy
- **Generic:** Settings page, description views (all connectors use same UI)
- **Connector-Specific:** Business-logic views only (calendar picker, file browser, etc.)

### First Four Connectors
1. Google Calendar (read/write events)
2. Microsoft Outlook Calendar (read/write events)
3. Slack (send messages, webhooks)
4. Google Drive (browse and attach files)

---

## Directory Structure

```
app/
  connectors/
    base_connector.rb           # Abstract base class + DSL
    registry.rb                 # Self-registration system
    stub.rb                     # Test connector
    google_calendar.rb          # (Phase 3)
    microsoft_outlook.rb        # (Phase 4)
    google_drive.rb             # (Phase 6)
    slack.rb                    # (Phase 5)

  controllers/connectors/
    base_controller.rb          # Auth + org context
    connector_accounts_controller.rb  # index/destroy/test/pause/resume
    oauth_controller.rb         # authorize + callback
    settings_controller.rb      # show/update (generic)
    calendars/
      google/
        calendars_controller.rb
        events_controller.rb
      microsoft/
        calendars_controller.rb
        events_controller.rb
    storage/
      google_drive/
        files_controller.rb
    messaging/
      slack/
        channels_controller.rb
        webhooks_controller.rb

  models/connectors/
    account.rb                  # OAuth accounts + encrypted tokens
    setting.rb                  # Schema-driven settings
    sync_log.rb                 # Audit trail
    event_mapping.rb            # External ↔ local ID mapping

  services/connectors/
    base_service.rb             # Base with sync logging + token refresh
    oauth_service.rb            # Token exchange/refresh/revoke
    sync_service.rb             # Bidirectional sync pattern
    calendars/
      google/
        oauth_service.rb
        calendar_fetch_service.rb
        event_sync_service.rb
      microsoft/
        oauth_service.rb
        calendar_fetch_service.rb
        event_sync_service.rb
    storage/
      google_drive/
        oauth_service.rb
        file_service.rb
    messaging/
      slack/
        oauth_service.rb
        message_service.rb
        webhook_service.rb
    stub/
      oauth_service.rb          # Test provider (Phase 2)

  jobs/connectors/
    base_job.rb                 # Error handling + auth context
    token_refresh_job.rb        # Proactive token refresh
    calendars/google/sync_job.rb
    calendars/microsoft/sync_job.rb
    storage/google_drive/sync_job.rb
    messaging/slack/notify_job.rb

  policies/connectors/
    account_policy.rb           # User-scoped; users manage own accounts

  views/connectors/
    connector_accounts/
      index.html.erb            # "My Connections" dashboard
    settings/
      show.html.erb             # Generic schema-driven settings
    oauth/
      callback.html.erb         # Success/failure landing
    calendars/
      shared/
        _calendar_picker.html.erb
        _event_list.html.erb
      google/calendars/index.html.erb
      google/events/index.html.erb
      microsoft/calendars/index.html.erb
      microsoft/events/index.html.erb
    storage/google_drive/files/index.html.erb
    messaging/slack/channels/index.html.erb

  javascript/controllers/connectors/
    oauth_popup_controller.js   # OAuth popup flow

db/
  migrate/
    20260319000000_create_connector_accounts.rb
    20260319000001_create_connector_settings.rb
    20260319000002_create_connector_sync_logs.rb
    20260319000003_create_connector_event_mappings.rb

docs/
  CONNECTORS_SECURITY.md        # Multi-layer auth + encryption
  CONNECTORS_OAUTH.md           # OAuth flow + implementation guide
  CONNECTORS_ARCHITECTURE_PLAN.md (this file)
```

---

## Database Schema

### connector_accounts
```sql
id uuid pk, user_id uuid fk, organization_id uuid fk,
provider varchar, provider_uid varchar,
display_name varchar, email varchar,
access_token_encrypted text, refresh_token_encrypted text,
token_expires_at timestamptz, token_scope varchar,
status varchar (active|paused|revoked|errored),
last_sync_at timestamptz, last_error text, error_count int,
metadata jsonb
UNIQUE (user_id, provider, provider_uid)
```

### connector_settings
```sql
id uuid pk, connector_account_id uuid fk,
key varchar, value text
UNIQUE (connector_account_id, key)
```

### connector_sync_logs
```sql
id uuid pk, connector_account_id uuid fk,
operation varchar, status varchar (pending|in_progress|success|failure),
records_processed/created/updated/failed int,
error_message text, duration_ms int,
started_at timestamptz, completed_at timestamptz
```

### connector_event_mappings
```sql
id uuid pk, connector_account_id uuid fk,
external_id varchar, external_type varchar,
local_type varchar, local_id uuid,
sync_direction varchar (push|pull|both),
last_synced_at timestamptz, external_etag varchar,
metadata jsonb
UNIQUE (connector_account_id, external_id, external_type)
```

---

## Key Base Classes

### Connectors::BaseConnector
Abstract class with class-level DSL for metadata:
```ruby
class MyConnector < Connectors::BaseConnector
  connector_key "my_service"
  connector_name "My Service"
  connector_category "messaging"
  connector_icon "icon-name"
  connector_description "Description"
  requires_oauth true
  oauth_scopes ["read", "write"]
  settings_schema(
    sync_direction: { type: :select, options: ["pull", "push", "both"] }
  )

  def pull; end
  def push(data); end
  def test_connection; end
end
```

Instance methods:
- `connected?` - Returns true if active with valid token
- `token_expired?` - Returns true if token_expires_at < now
- Abstract methods: `pull`, `push`, `test_connection`

### Connectors::Registry
Self-registration system:
```ruby
Connectors::Registry.register(Connectors::MyConnector)
Connectors::Registry.find("my_service")
Connectors::Registry.all
Connectors::Registry.by_category("messaging")
```

### Connectors::BaseService
Service pattern with sync logging and token refresh:
```ruby
class MyService < Connectors::BaseService
  def call
    ensure_fresh_token!
    with_sync_log(operation: "fetch") do |log|
      # Perform operation, returns data
    end
  end
end
```

Protected methods:
- `with_sync_log(operation:)` - Wraps yield, tracks status/duration/errors
- `ensure_fresh_token!` - Calls provider's OauthService to refresh if expired
- `connector` - Get connector instance

### Connectors::OauthService
Token management contract:
```ruby
class Provider::OauthService < Connectors::OauthService
  def exchange_code!(code, redirect_uri, user, organization)
    # HTTP to provider, return success(data: account)
  end

  def refresh_token!
    # Refresh expired token, return success
  end

  def revoke!
    # Clear local tokens (provider revocation is optional)
  end
end
```

Protected helpers:
- `save_tokens!(access_token:, refresh_token:, expires_in:)`
- `generate_state`, `verify_state`

---

## Multi-Layer Authorization

### Layer 1: Controller
```ruby
before_action :authenticate_user!
authorize @connector_account, policy_class: AccountPolicy
```

### Layer 2: Service Initialization
```ruby
def initialize(connector_account:)
  raise unless Current.user.present?
  raise unless connector_account.user_id == Current.user.id
end
```

### Layer 3: Connector Initialization
Same checks as service (defense-in-depth)

### Layer 4: Job Initialization
```ruby
def perform(connector_account_id:)
  @connector_account = Account.find(connector_account_id)
  raise unless @connector_account.user.present?
  raise unless @connector_account.organization.present?
end
```

---

## Routes

```ruby
namespace :connectors do
  resources :connector_accounts, only: [:index, :destroy] do
    member { patch :pause; patch :resume; post :test }
    collection { get :available }
  end

  resources :settings, only: [:show, :update], param: :connector_account_id

  scope :oauth, controller: "oauth" do
    get ":provider/authorize", action: :authorize, as: :oauth_authorize
    get ":provider/callback", action: :callback, as: :oauth_callback
  end

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

  namespace :storage do
    namespace :google_drive do
      resources :files, only: [:index]
    end
  end

  namespace :messaging do
    namespace :slack do
      resources :channels, only: [:index]
      post "webhooks", to: "webhooks#receive"
    end
  end
end
```

---

## Generic View Strategy

### connector_accounts/index.html.erb
- Lists connected accounts + status
- Shows available services from `Connectors::Registry`
- Generic card rendering from connector metadata (no provider-specific code)

### settings/show.html.erb
- Renders schema-driven form fields from connector.settings_schema
- Supports field types: :select, :boolean, :list_select, :text
- Optionally renders provider-specific partial if exists

### Business-Logic Views
- calendar_picker.html.erb - Connector-specific
- file_browser.html.erb - Connector-specific
- channel_picker.html.erb - Connector-specific

---

## Phased Implementation Roadmap

### Phase 1: Foundation ✅
**Duration:** 2-3 days
- 4 migrations + models (Account, Setting, SyncLog, EventMapping)
- BaseConnector, Registry, BaseService, BaseJob
- Controllers: Base, ConnectorAccounts, Settings, OAuth
- Generic views + Stimulus controller
- Authorization (AccountPolicy)
- Multi-layer auth implementation
- **Deliverable:** `/connectors/accounts` shows empty catalog, routes ready

### Phase 2: OAuth Infrastructure ✅
**Duration:** 1-2 days
- OauthService (exchange, refresh, revoke)
- TokenRefreshJob (proactive refresh before expiry)
- Stub provider + stub connector (full testing)
- CSRF protection (state parameter validation)
- Token encryption (AES-256)
- Comprehensive test suite (services, integration, end-to-end)
- **Deliverable:** Full OAuth round-trip works, stub provider tests pass

### Phase 3: Google Calendar
**Duration:** 3-4 days
- Google OAuth service (Google Cloud credentials)
- Calendar fetch service (list calendars)
- Event sync service (create/update/delete)
- GoogleCalendar connector manifest
- Views: calendar picker, event list, sync control
- SyncJob + Google Calendar webhook handling
- Tests + integration
- **Deliverable:** Connect Google Calendar → pick calendar → events appear

### Phase 4: Microsoft Outlook Calendar
**Duration:** 2-3 days
- Microsoft Graph OAuth service (Azure app registration)
- Calendar fetch service (Microsoft Graph API)
- Event sync service
- MicrosoftOutlook connector manifest
- Reuse calendar picker partial from Phase 3
- **Deliverable:** Connect Outlook → same calendar flow

### Phase 5: Slack
**Duration:** 2-3 days
- Slack OAuth service
- Message service (post to channel)
- Webhook receiver (public endpoint, Slack-signed)
- Slack connector manifest
- Integration: ListItem completed → SlackNotifyJob
- **Deliverable:** Create item → post to Slack channel

### Phase 6: Google Drive
**Duration:** 2 days
- Google Drive OAuth service (reuse Google patterns from Phase 3)
- File service (list files, get metadata)
- File browser UI
- GoogleDrive connector manifest
- Attach files to ListItems
- **Deliverable:** Browse Google Drive → attach files to items

---

## Gem Extraction Path

Each connector's files are fully self-contained:

```ruby
# Future gem: listopia-google-calendar

class Railtie < Rails::Railtie
  config.after_initialize do
    Connectors::Registry.register(
      ListopiaGoogleCalendar::Connector
    )
  end
end
```

**Zero changes** needed to:
- Host app ConnectorAccount model
- Generic views
- Controllers
- Authorization policies

---

## Verification Checklist (Per Phase)

### Phase 1
- [ ] `/connectors/accounts` renders with empty catalog
- [ ] Click "Connect" redirects to OAuth
- [ ] OAuth callback creates ConnectorAccount
- [ ] Settings page shows schema-driven form
- [ ] Can disconnect account
- [ ] `rubocop app/connectors app/controllers/connectors app/services/connectors` passes
- [ ] `bundle exec rspec spec/connectors/` passes

### Phase 2
- [ ] Authorization flow works end-to-end (with stub provider)
- [ ] State parameter prevents CSRF (invalid state rejected)
- [ ] Tokens are encrypted in database
- [ ] TokenRefreshJob refreshes tokens before expiry
- [ ] Account status changes to :errored on failure
- [ ] `bundle exec rspec spec/services/connectors/` passes

### Phase 3+
- [ ] Connector shows in "Available Services"
- [ ] OAuth connect → redirect to provider → exchange code → account created
- [ ] Connector operations (pull/push) work with real API
- [ ] SyncJob runs on schedule
- [ ] Tests pass for provider-specific services

---

## Security & Compliance

### Encryption
- Tokens encrypted with AES-256 (Rails 8.1 key_generator)
- Keys derived from `config/credentials.yml.enc`
- Fallback to generated keys in test/dev

### Authorization
- User-scoped accounts (user_id == Current.user.id)
- Multi-layer checks (controller → service → connector)
- CSRF protection via state parameter validation

### Audit Trail
- Every operation logged in connector_sync_logs
- Error messages and status tracking
- User can view sync history per account

### Token Refresh
- Proactive refresh before expiry (1 hour window)
- Graceful failure with error state tracking
- Background job ensures fresh tokens

---

## Future Enhancements

1. **Rate Limiting:** Limit connector operations per time window
2. **Scope Validation:** Periodically verify OAuth scopes
3. **Webhook Signing:** Validate provider webhooks
4. **Audit Logging:** Compliance-grade operation tracking
5. **Consent Management:** Manage OAuth consent/revocation
6. **Parallel Sync:** Queue multiple connector syncs
7. **Conflict Resolution:** Handle sync conflicts gracefully
8. **Provider Webhooks:** Real-time updates vs polling

---

## Related Documentation

- `CONNECTORS_SECURITY.md` - Authorization, encryption, incident handling
- `CONNECTORS_OAUTH.md` - OAuth flow, implementation guide for providers
- `REAL_TIME.md` - Turbo Streams for real-time connector updates
- `SERVICE_BROADCASTING.md` - Broadcast sync status to users

---

## Key Principles

1. **User-Scoped:** All data belongs to a user, not organization
2. **Encrypted:** Tokens never stored or transmitted in plaintext
3. **Audited:** Every operation logged with status and duration
4. **Extensible:** New connectors require zero core changes
5. **Self-Contained:** Each connector can be extracted as a gem
6. **Defensible:** Multi-layer authorization at every boundary
7. **Resilient:** Graceful error handling with recovery

