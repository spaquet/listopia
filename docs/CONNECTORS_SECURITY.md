# Connectors Security Model

## Authentication & Authorization

All connector operations require strict authentication and authorization checks at multiple layers:

### 1. **Controller Level** (First Line of Defense)
- `Connectors::BaseController` includes `before_action :authenticate_user!`
- All routes require authenticated session
- `Connectors::OauthController` explicitly calls `authenticate_user!` in authorize and callback actions
- Pundit policies enforce user ownership: `record.user_id == user.id`

### 2. **Service Level** (Second Line of Defense)
- `Connectors::BaseService.initialize` verifies:
  - `Current.user` is present
  - Account belongs to current user: `connector_account.user_id == Current.user.id`
- Raises `StandardError` if either check fails
- All connector operations flow through services

### 3. **Connector Level** (Third Line of Defense)
- `Connectors::BaseConnector.initialize` performs the same checks:
  - `Current.user` is present
  - Account belongs to current user
- Acts as a final guard against direct instantiation

### 4. **Job Level** (For Background Operations)
- `Connectors::BaseJob.perform` verifies:
  - Account exists
  - Account's user still exists
  - Account's organization still exists
- Jobs run in system context (no user), so we validate data integrity

## OAuth Security

### State Parameter (CSRF Protection)
- `OauthController#authorize` generates a random state token
- State is stored in session: `session[:oauth_state]`
- `OauthController#callback` validates state before exchanging code
- Invalid/missing state triggers error: "Invalid OAuth state - possible CSRF attack"

### Token Storage
- Access tokens and refresh tokens are encrypted in database
- Uses Rails 8.1 `key_generator` with 32-byte keys (AES-256)
- Tokens never appear in logs, sessions, or responses in plaintext
- Decryption only happens when needed for API calls

### Code Exchange
- Authorization code is exchanged for tokens immediately
- Code is not stored; only tokens are persisted (encrypted)
- Tokens are scoped to specific OAuth scopes per provider
- Token expiry is tracked; expired tokens trigger refresh

## User Isolation

### Data Scoping
- `Connectors::Account` is uniquely scoped: `(user_id, provider, provider_uid)`
- Prevents users from seeing/managing other users' accounts
- `ConnectorAccountPolicy::Scope` returns only current user's accounts

### Multi-Tenant Consideration
- Accounts are user-level, not organization-level
- Each user manages their own OAuth connections
- Organizations can view user's public list integrations but not OAuth credentials
- Helpful for: Calendar invites use user's default calendar, not org's

## Incident Handling

### Error States
- Failed operations update `connector_account.status` to `:errored`
- Error message stored in `connector_account.last_error`
- Error count incremented; can be monitored for abuse
- Sync logs capture all operation history for audit

### Token Invalidation
- User can disconnect account via `destroy` action
- Disconnection sets `status: :revoked` and clears encrypted tokens
- Prevents future API calls with revoked credentials
- History is preserved in sync logs

## Deployment Requirements

### Required Configuration
```yaml
# config/credentials.yml.enc
connector_tokens:
  secret: "<64-character-hex-key>" # openssl rand -hex 32
```

In test/dev environments, a temporary key is generated per request.

### Environment-Specific Notes
- **Production**: Must provide stable secret key in credentials
- **Development**: Auto-generated keys work fine
- **Test**: Unique key per test; encryption state is isolated

## Future Enhancements

1. **Rate Limiting**: Add connector operation rate limits
2. **Audit Logging**: Extended logging for compliance (SOC 2, etc.)
3. **Scope Validation**: Periodically verify OAuth scopes match requirements
4. **Token Rotation**: Automatic refresh before expiry (already in TokenRefreshJob)
5. **Revocation Webhook**: Handle provider-initiated revocations
