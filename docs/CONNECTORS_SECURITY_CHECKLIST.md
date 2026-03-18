# Connectors Security Implementation Checklist

## Pre-Testing Security Verification

This checklist ensures all security requirements are met before testing connector functionality in development or production.

---

## ✅ 1. Token Encryption & Storage

- [x] **Token Encryption at Rest**
  - Account model uses `ActiveSupport::MessageEncryptor` (AES-256-GCM)
  - Both `access_token` and `refresh_token` are encrypted before storage
  - Encryption happens via setters: `account.access_token = token`
  - Decryption happens via getters: `account.access_token`
  - Invalid/corrupted ciphertext gracefully returns nil

- [x] **Encryption Key Management**
  - Production: Use `Rails.application.credentials.dig(:connector_tokens, :secret)`
  - Development/Test: Auto-generates 32-byte key via `key_generator`
  - Key length verified: 32 bytes (256 bits) for AES-256
  - Command to generate key: `openssl rand -hex 32`

- [x] **Token Never in Plaintext**
  - Database: Stored encrypted as `*_encrypted` columns
  - Logs: Never logged (decryption happens only during API calls)
  - Sessions: Not stored in session or cookies
  - API responses: Tokens never returned to client
  - Credentials file: Must be in .gitignore (encrypted by Rails)

**Verification Steps Before Testing:**
```bash
# 1. Check credentials file exists and is encrypted
cat config/credentials.yml.enc | head -1  # Should show binary/unreadable data

# 2. Verify encryption key is set (or auto-generates)
rails c -e development
account = Connectors::Account.first
account.access_token = "test_token"
account.save!
Connectors::Account.connection.execute("SELECT access_token_encrypted FROM connector_accounts WHERE id = '#{account.id}'")[0].inspect
# Should show encrypted hex string, NOT "test_token"

# 3. Verify decryption works
account.reload
account.access_token  # Should return "test_token"
```

---

## ✅ 2. Multi-Layer Authorization

### Controller Layer (First Defense)
- [x] `Connectors::BaseController` includes `before_action :authenticate_user!`
- [x] All routes protected by authentication
- [x] `OauthController#authorize` explicitly calls `authenticate_user!`
- [x] `OauthController#callback` validates state before token exchange

**Verification:**
```ruby
# Test unauthenticated access
visit connectors_connector_accounts_path
# Should redirect to sign_in
```

### Service Layer (Second Defense)
- [x] `Connectors::BaseService.initialize` verifies:
  - `Current.user.present?`
  - `connector_account.user_id == Current.user.id`
- [x] Raises error on any check failure
- [x] All API operations flow through services

**Verification:**
```ruby
# Test with wrong user
user1 = create(:user)
user2 = create(:user)
account = create(:connectors_account, user: user1)

Current.user = user2
service = Connectors::Google::CalendarFetchService.new(connector_account: account)
# Should raise "User does not own this connector account"
```

### Connector Level (Third Defense)
- [x] `Connectors::BaseConnector.initialize` performs same checks
- [x] Acts as final guard against direct instantiation

**Verification:**
```ruby
Current.user = create(:user)
wrong_account = create(:connectors_account, user: create(:user))
Connectors::GoogleCalendar.new(wrong_account)
# Should raise error
```

### Job Level (Background Operations)
- [x] `Connectors::BaseJob.perform` verifies:
  - Account exists
  - Account's user still exists
  - Account's organization still exists
- [x] Jobs run in system context (no user), so we validate data integrity

**Verification:**
```ruby
account = create(:connectors_account)
Connectors::Calendars::Google::SyncJob.perform_now(
  connector_account_id: account.id
)
# Should succeed

# Delete user and try again
account.user.delete
Connectors::Calendars::Google::SyncJob.perform_now(
  connector_account_id: account.id
)
# Should fail gracefully
```

### Policy Layer (Data Scoping)
- [x] `Connectors::AccountPolicy::Scope` returns only current user's accounts
- [x] Cannot access/manage other users' accounts

**Verification:**
```ruby
user1 = create(:user)
user2 = create(:user)
account1 = create(:connectors_account, user: user1)
account2 = create(:connectors_account, user: user2)

Current.user = user1
policy_scope = Connectors::AccountPolicy::Scope.new(user1, Connectors::Account).resolve
policy_scope.include?(account1)  # true
policy_scope.include?(account2)  # false
```

---

## ✅ 3. OAuth Security

### CSRF Protection (State Parameter)
- [x] State token generated per authorization request
- [x] State stored in session (secure, HTTP-only, same-site)
- [x] State validated on callback
- [x] Missing/invalid state triggers error

**Verification Steps:**
```ruby
# 1. Test valid flow
visit connectors_oauth_authorize_path(provider: "google_calendar")
# Check session[:oauth_state] is set
# Callback with correct state should succeed

# 2. Test invalid state
visit connectors_oauth_callback_path(
  provider: "google_calendar",
  code: "test_code",
  state: "invalid_state"
)
# Should show error: "Invalid OAuth state - possible CSRF attack"

# 3. Test missing state
visit connectors_oauth_callback_path(
  provider: "google_calendar",
  code: "test_code"
)
# Should show error
```

### Token Exchange Security
- [x] Authorization code exchanged immediately for tokens
- [x] Code is NOT stored; only tokens are persisted
- [x] Tokens are scoped to specific OAuth scopes
- [x] Token expiry tracked and refreshed automatically

**Verification:**
```ruby
# Check code is not in database
Connectors::Account.pluck(:access_token_encrypted, :refresh_token_encrypted)
# Should not contain raw authorization codes

# Check token refresh works
account = create(:connectors_account, token_expires_at: 1.hour.ago)
Connectors::TokenRefreshJob.perform_now(
  connector_account_id: account.id
)
# Should update token_expires_at to future
```

### Scope Validation
- [x] Each connector declares required scopes
- [x] OAuth request includes all required scopes
- [x] Token scope stored: `account.token_scope`

**Verification:**
```ruby
# Check scopes are enforced
google_calendar_scopes = Connectors::GoogleCalendar.oauth_scopes_list
# Should include calendar.readonly and calendar.events

# Check account stores scope
account = create(:connectors_account, token_scope: "calendar.readonly calendar.events")
account.token_scope  # Should match required scopes
```

---

## ✅ 4. Data Isolation & Multi-Tenancy

### User-Level Accounts
- [x] Accounts are user-scoped, not organization-scoped
- [x] Unique constraint: `(user_id, provider, provider_uid)`
- [x] User can have multiple accounts from same provider

**Verification:**
```ruby
user = create(:user)

# Can create multiple accounts from same provider
account1 = create(:connectors_account,
  user: user,
  provider: "google_calendar",
  provider_uid: "user1@gmail.com"
)
account2 = create(:connectors_account,
  user: user,
  provider: "google_calendar",
  provider_uid: "user2@gmail.com"
)
# Both should exist

# Different user can have account from same UID
other_user = create(:user)
account3 = create(:connectors_account,
  user: other_user,
  provider: "google_calendar",
  provider_uid: "user1@gmail.com"
)
# All should exist independently
```

### Organization Isolation
- [x] Accounts are user-owned
- [x] Organizations cannot access user's raw credentials
- [x] Organizations can view user's public integration status

**Verification:**
```ruby
user = create(:user)
org = create(:organization)
account = create(:connectors_account, user: user, organization: org)

Current.user = create(:user, organizations: [org])
Current.organization = org

# Should not be able to access other user's account tokens
other_account = create(:connectors_account, user: create(:user))
Connectors::AccountPolicy.new(Current.user, other_account).show?  # false
```

---

## ✅ 5. Error Handling & Incident Response

### Error State Management
- [x] Failed operations set `status: :errored`
- [x] Error message stored in `last_error`
- [x] Error count tracked
- [x] All operations logged in sync_logs

**Verification:**
```ruby
account = create(:connectors_account)

# Simulate failed API call
Connectors::Google::CalendarFetchService.new(connector_account: account)
# ... API fails ...

account.reload
account.status  # Should be :errored
account.last_error  # Should contain error message
account.error_count  # Should be > 0
```

### Token Invalidation
- [x] Disconnection sets `status: :revoked`
- [x] Tokens cleared on revocation
- [x] History preserved in audit logs

**Verification:**
```ruby
account = create(:connectors_account)
original_token = account.access_token

# Revoke account
account.destroy

# Check cannot reuse
Connectors::Account.find_by(id: account.id)  # nil - soft delete not used

# Check history exists
Connectors::SyncLog.where(connector_account_id: account.id).count  # > 0
```

### Webhook Signature Verification
- [x] All Slack webhooks verified with HMAC-SHA256
- [x] Signature verification uses constant-time comparison
- [x] Timestamp validation (must be within 5 minutes)
- [x] Invalid signatures rejected

**Verification:**
```ruby
# Test signature verification
signing_secret = "test_secret"
timestamp = Time.current.to_i.to_s
body = '{"type":"event_callback"}'

base_string = "v0:#{timestamp}:#{body}"
signature = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', signing_secret, base_string)}"

result = Connectors::Slack::WebhookService.verify_request(timestamp, signature, body)
result  # Should be true

# Test invalid signature
result = Connectors::Slack::WebhookService.verify_request(timestamp, "v0=invalid", body)
result  # Should be false

# Test old timestamp (> 5 minutes)
old_timestamp = (Time.current - 10.minutes).to_i.to_s
result = Connectors::Slack::WebhookService.verify_request(old_timestamp, signature, body)
result  # Should be false
```

---

## ✅ 6. Logging & Audit Trail

### Sync Logs
- [x] All operations logged in `connector_sync_logs` table
- [x] Log includes: operation, status, records processed, duration, timestamps
- [x] Failed operations include error_message
- [x] Cannot be modified/deleted (audit-only)

**Verification:**
```ruby
account = create(:connectors_account)

# Perform operation
Connectors::Google::CalendarFetchService.new(
  connector_account: account
).fetch_calendars

# Check log created
log = Connectors::SyncLog.last
log.operation  # "fetch_calendars"
log.status  # "success"
log.connector_account_id  # account.id
log.started_at  # timestamp
log.completed_at  # timestamp
log.duration_ms  # milliseconds
```

### Error Logging
- [x] Errors logged via `Rails.logger`
- [x] No sensitive data (tokens, emails) in logs
- [x] Error counts tracked for monitoring

**Verification:**
```bash
# Check logs do NOT contain tokens
grep -r "access_token" log/development.log
# Should be empty or only encrypted references

# Check error messages are descriptive
grep -r "Slack API error\|Google API error" log/development.log
# Should show API error messages, not tokens
```

---

## ✅ 7. Deployment Security

### Required Configuration
Before deploying to production:

```bash
# 1. Generate encryption key
openssl rand -hex 32
# Output: abc123def456...

# 2. Add to credentials.yml.enc
EDITOR=nano rails credentials:edit
# Add:
# connector_tokens:
#   secret: "abc123def456..."

# 3. Verify key is encrypted
cat config/credentials.yml.enc | xxd | head -5
# Should show binary/unreadable data

# 4. Verify key works in production
RAILS_ENV=production rails c
Rails.application.credentials.dig(:connector_tokens, :secret)
# Should return 64-character hex string

# 5. Test encryption/decryption
account = Connectors::Account.first
account.access_token  # Should work
```

### Environment Variables
- [x] Never store tokens in ENV vars
- [x] Use `Rails.application.credentials` for secrets
- [x] Client IDs/secrets in credentials (safe)
- [x] API keys in credentials (safe)

**What goes where:**
```yaml
# config/credentials.yml.enc (SAFE - encrypted)
google_calendar:
  client_id: "..."
  client_secret: "..."
slack:
  client_id: "..."
  client_secret: "..."
  signing_secret: "..."
connector_tokens:
  secret: "..." # 32-byte hex

# .env or ENV vars (AVOID for tokens)
# Only use for:
# - Feature flags (RAILS_LOG_LEVEL)
# - Environment names
# - Non-sensitive configuration
```

---

## ✅ 8. Rate Limiting & Abuse Prevention

### Current Implementation
- [x] Token refresh proactive (before expiry)
- [x] Error count tracked
- [x] Status field tracks account health

### Recommended Additions (Future)
- [ ] Rate limit connector API calls per user
- [ ] Monitor error_count for abuse patterns
- [ ] Automatic pause on repeated failures
- [ ] Alert on unusual access patterns

---

## ✅ 9. Secrets Rotation

### Current Process
1. User revokes old account (via UI or `account.destroy`)
2. Old tokens are deleted/overwritten
3. User reconnects with new authorization

### Recommended Enhancements (Future)
1. Add `revoked_at` timestamp
2. Add `revoked_by` (user_id or system)
3. Automatic rotation before expiry for refresh tokens
4. Notification to user on token changes

---

## Testing Checklist

Run these before testing in development or staging:

```bash
# 1. Unit tests
bundle exec rspec spec/models/connectors/
bundle exec rspec spec/services/connectors/
bundle exec rspec spec/controllers/connectors/
bundle exec rspec spec/policies/connectors/

# 2. Integration tests
bundle exec rspec spec/integration/connectors/

# 3. Security verification (manual)
rails c

# Verify encryption
account = Connectors::Account.first
account.access_token = "test_token_#{Time.current.to_i}"
account.save!
connection_result = Connectors::Account.connection.execute(
  "SELECT access_token_encrypted FROM connector_accounts LIMIT 1"
)
puts "Encrypted: #{connection_result[0]['access_token_encrypted']}"
puts "Decrypted: #{account.access_token}"

# Verify authorization
Current.user = create(:user)
other_account = create(:connectors_account, user: create(:user))
begin
  Connectors::Google::CalendarFetchService.new(connector_account: other_account)
rescue => e
  puts "Authorization check working: #{e.message}"
end

# Verify webhook signature
timestamp = Time.current.to_i.to_s
body = '{"test":"data"}'
secret = "test_secret"
base = "v0:#{timestamp}:#{body}"
sig = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', secret, base)}"
result = Connectors::Slack::WebhookService.verify_request(timestamp, sig, body)
puts "Webhook signature verification: #{result}"

# 4. Run security linter
bundle exec brakeman -z

# 5. Check for exposed secrets
bundle exec bundle-audit check
```

---

## Production Checklist

Before deploying to production:

- [ ] Encryption key configured in `config/credentials.yml.enc`
- [ ] Credentials file NOT in git history
- [ ] All tests passing (`bundle exec rspec spec/connectors/`)
- [ ] Security audit passed (`bundle exec brakeman`)
- [ ] Rate limiting configured (if needed)
- [ ] Monitoring/alerting set up for error_count
- [ ] Backup/disaster recovery plan for connector_accounts table
- [ ] Data retention policy defined
- [ ] GDPR/compliance review completed
- [ ] Incident response plan documented
- [ ] SSL/TLS enforced for all OAuth redirects
- [ ] All external API calls use HTTPS
- [ ] CORS properly configured for webhook endpoints

---

## Incident Response Procedures

### If Token Compromised
1. User disconnects account (sets `status: :revoked`)
2. All future API calls fail (no valid token)
3. User reconnects to authorize new token
4. Check sync_logs for unauthorized access patterns

### If OAuth Secret Leaked
1. Immediately invalidate leaked secret in provider dashboard
2. Generate new client secret
3. Update Rails credentials
4. Users may need to reconnect (if old secret was compromised)

### If Encryption Key Compromised
1. Generate new encryption key: `openssl rand -hex 32`
2. Update credentials.yml.enc
3. Re-encrypt all tokens: See migration strategy below

**Re-encrypt all tokens (if key compromised):**
```ruby
# Create migration
# Re-read and re-save to re-encrypt with new key
Connectors::Account.find_each do |account|
  # Decrypts with old key, encrypts with new key
  account.update!(access_token: account.access_token, refresh_token: account.refresh_token)
end
```

---

## References

- `CONNECTORS_SECURITY.md` - Detailed security model
- `CONNECTORS_OAUTH.md` - OAuth 2.0 implementation
- `CONNECTORS_ARCHITECTURE.md` - Full architecture overview
