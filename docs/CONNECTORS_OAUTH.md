# OAuth Infrastructure Implementation

## Phase 2: OAuth Token Management

Complete OAuth 2.0 implementation for secure third-party service integration.

### Components Implemented

#### 1. **OauthService Base Class**
```ruby
# app/services/connectors/oauth_service.rb
class Connectors::OauthService < ApplicationService
  # Subclass methods (provider-specific):
  # - exchange_code!(code, redirect_uri, user, organization)
  # - refresh_token!
  # - authorization_url(redirect_uri:, state:)

  # Shared methods:
  # - revoke!
  # - save_tokens!(access_token:, refresh_token:, expires_in:)
  # - generate_state, verify_state
end
```

**Responsibility:** Define OAuth contract and shared token management logic

#### 2. **Stub OAuth Provider** (Testing)
```ruby
# app/services/connectors/stub/oauth_service.rb
class Connectors::Stub::OauthService < Connectors::OauthService
  # Full OAuth 2.0 simulation:
  # ✓ Authorization URL generation with state parameter
  # ✓ Code exchange for tokens
  # ✓ Token refresh before expiry
  # ✓ Token revocation
end
```

**Responsibility:** Testing connector without external dependencies

#### 3. **Stub Connector**
```ruby
# app/connectors/stub.rb
class Connectors::Stub < Connectors::BaseConnector
  # Features:
  # ✓ Class-level metadata (DSL)
  # ✓ OAuth required with scopes
  # ✓ Settings schema (sync_direction, auto_sync)
  # ✓ Test connection, pull, push operations

  # Auto-registers: Connectors::Registry.register(Connectors::Stub)
end
```

**Responsibility:** Demonstrate complete connector pattern

#### 4. **Token Refresh Job**
```ruby
# app/jobs/connectors/token_refresh_job.rb
class Connectors::TokenRefreshJob < Connectors::BaseJob
  # Features:
  # ✓ Proactive refresh before expiry (1 hour before)
  # ✓ Skip if already fresh
  # ✓ Graceful error handling
  # ✓ Current context setup for authorization

  # Schedule: Can be run via `whenever` gem on cron schedule
end
```

**Responsibility:** Keep tokens fresh automatically

### OAuth Flow Diagram

```
User                   App                    OAuth Provider
  |                     |                          |
  |--Click Connect----->|                          |
  |                     |                          |
  |                     |<----Authorization URL----| (with state)
  |<----Redirect--------|                          |
  |                     |                          |
  |--Approve Access---->|                          |
  |                     |                          |
  |                     |<----Auth Code + State----|
  |<----Redirect--------|                          |
  |                     |                          |
  |                     |--Exchange Code---------->|
  |                     |<----Access Token---------|
  |                     |                          |
  |<---Settings Page----|                          |
  |                     |                          |
```

### Security Features

#### State Parameter (CSRF Protection)
```ruby
# Authorize action:
state = SecureRandom.urlsafe_base64
session[:oauth_state] = state
redirect_to provider.authorization_url(state: state)

# Callback action:
unless params[:state] == session.delete(:oauth_state)
  raise "Invalid OAuth state - possible CSRF attack"
end
```

#### Token Storage
- Access tokens encrypted with AES-256
- Refresh tokens encrypted with AES-256
- Tokens never exposed in logs or sessions
- Expiration tracked; refresh before expiry

#### Token Lifecycle

```
1. Exchange Phase
   ├─ Authorization code → OAuth provider
   ├─ Receive: access_token, refresh_token, expires_in
   └─ Save (encrypted) with expiration timestamp

2. Refresh Phase (Proactive)
   ├─ Check: token_expires_at < 1.hour.from_now?
   ├─ Request: refresh_token → OAuth provider
   ├─ Receive: new access_token, new expiration
   └─ Update (encrypted) token and expiration

3. Revocation Phase
   ├─ User clicks "Disconnect"
   ├─ Call: revoke! service
   ├─ Clear: access_token_encrypted, refresh_token_encrypted
   └─ Set: status = :revoked
```

### Testing Infrastructure

#### 1. Service Tests
```ruby
# spec/services/connectors/oauth_service_spec.rb
- Test token revocation
- Test token saving with expiration
- Test error handling
```

#### 2. Stub Provider Tests
```ruby
# spec/services/connectors/stub/oauth_service_spec.rb
- Authorization URL generation
- Code exchange (valid/invalid)
- User ID extraction from code
- Token refresh flow
- Token revocation
```

#### 3. Integration Tests
```ruby
# spec/integration/connectors/oauth_flow_spec.rb
- Complete OAuth flow (authorize → callback → connected)
- CSRF protection (state validation)
- Error scenarios (invalid code, provider errors, missing code)
- Connected account management
- Token refresh job triggering
```

#### 4. Connector Tests
```ruby
# spec/connectors/stub_spec.rb
- Metadata and settings schema
- Connection testing
- Pull/push operations
- Registry integration
```

### How to Implement a Real Provider

#### Step 1: Create Provider Service
```ruby
# app/services/connectors/google_calendar/oauth_service.rb
module Connectors
  module GoogleCalendar
    class OauthService < Connectors::OauthService
      OAUTH_HOST = "https://accounts.google.com"
      OAUTH_TOKEN_HOST = "https://oauth2.googleapis.com"

      def authorization_url(redirect_uri:, state:)
        uri = URI("#{OAUTH_HOST}/o/oauth2/v2/auth")
        uri.query = URI.encode_www_form(
          client_id: ENV["GOOGLE_OAUTH_CLIENT_ID"],
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: Connectors::GoogleCalendar.oauth_scopes.join(" "),
          state: state
        )
        uri.to_s
      end

      def exchange_code!(code, redirect_uri, user, organization)
        response = HTTP.post("#{OAUTH_TOKEN_HOST}/token",
          form: {
            client_id: ENV["GOOGLE_OAUTH_CLIENT_ID"],
            client_secret: ENV["GOOGLE_OAUTH_CLIENT_SECRET"],
            code: code,
            grant_type: "authorization_code",
            redirect_uri: redirect_uri
          }
        )

        data = JSON.parse(response.body)
        account = find_or_create_account(user, organization, data["id_token"])

        save_tokens!(
          access_token: data["access_token"],
          refresh_token: data["refresh_token"],
          expires_in: data["expires_in"]
        )

        success(data: account)
      end

      def refresh_token!
        # Similar implementation with refresh token
      end
    end
  end
end
```

#### Step 2: Create Connector Manifest
```ruby
# app/connectors/google_calendar.rb
class Connectors::GoogleCalendar < Connectors::BaseConnector
  connector_key "google_calendar"
  connector_name "Google Calendar"
  connector_category "calendars"
  connector_icon "calendar"
  # ... define connector
end
Connectors::Registry.register(Connectors::GoogleCalendar)
```

#### Step 3: Add OAuth Credentials
```yaml
# config/credentials.yml.enc
google_calendar:
  client_id: "..."
  client_secret: "..."
```

### Monitoring & Maintenance

#### Token Refresh Job Schedule
```ruby
# config/schedule.yml (whenever gem)
every 6.hours do
  runner "Connectors::Account.where('token_expires_at < ?', 1.hour.from_now).find_each { |a| Connectors::TokenRefreshJob.perform_later(connector_account_id: a.id) }"
end
```

#### Error Tracking
- Monitor `connector_accounts.last_error` for issues
- Check `connector_sync_logs` for operation history
- Alert when `error_count` exceeds threshold
- Notify user when account enters `:errored` status

### Extensibility

All new OAuth providers should:
1. Create `Connectors::{Provider}::OauthService` subclass
2. Create `Connectors::{Provider}` connector manifest
3. Add credentials to `config/credentials.yml.enc`
4. No changes needed to core controllers, views, or models!

The architecture supports gem extraction for enterprise connectors.
