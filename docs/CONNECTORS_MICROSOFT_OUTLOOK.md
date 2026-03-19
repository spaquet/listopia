# Microsoft Outlook Calendar Connector Implementation

## Overview

The Microsoft Outlook Calendar connector enables bidirectional event sync between Listopia and Outlook via Microsoft Graph API. Users can view, create, and update events through Listopia with automatic synchronization to their Outlook calendar.

## Architecture

Mirrors Google Calendar implementation but uses Microsoft Graph API instead:

### Components

1. **MicrosoftOutlook Connector** - Metadata and connector manifest
2. **OAuth Service** - Microsoft Identity Platform v2.0 with PKCE
3. **Calendar Fetch Service** - List Outlook calendars via Microsoft Graph
4. **Event Sync Service** - Bidirectional event sync (pull/push)
5. **Sync Job** - Background event synchronization
6. **Controllers** - Calendar selection and event viewing
7. **Views** - Calendar picker and event list (same UI as Google)

## Key Differences from Google Calendar

### OAuth Implementation
```
Google: OAuth 2.0 standard flow
Microsoft: OAuth 2.0 with PKCE (recommended for public clients)
```

### API Endpoints
```
Google: https://www.googleapis.com/calendar/v3/...
Microsoft: https://graph.microsoft.com/v1.0/me/calendars/...
```

### Event Property Names
```
Google:     Microsoft:
- summary   - subject
- description - bodyPreview
- start.dateTime - start.dateTime (same format)
- id        - id
- etag      - changeKey
```

### Scopes
```
Google:
- https://www.googleapis.com/auth/calendar
- https://www.googleapis.com/auth/calendar.events

Microsoft:
- Calendars.Read
- Calendars.ReadWrite
- offline_access (required for refresh tokens)
```

## Setup & Configuration

### 1. Azure Setup

```bash
# Create Azure app registration
# Configure redirect URI: https://yourdomain.com/connectors/oauth/microsoft_outlook/callback
# Create client secret
# Grant Calendar permissions: Calendars.Read, Calendars.ReadWrite
```

### 2. Store Credentials

```yaml
# config/credentials.yml.enc
microsoft_outlook:
  client_id: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  client_secret: "xxx~yyy~zzz~..."
```

Or environment variables:
```bash
MICROSOFT_OAUTH_CLIENT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
MICROSOFT_OAUTH_CLIENT_SECRET=xxx~yyy~zzz~...
```

### 3. Schedule Sync Job

```ruby
# config/schedule.yml
every 1.hour do
  runner "Connectors::Account.where(provider: 'microsoft_outlook', status: 'active').find_each { |a| Connectors::Calendars::Microsoft::SyncJob.perform_later(connector_account_id: a.id) }"
end
```

## OAuth Flow with PKCE

```
1. Generate code_verifier (random 32-byte string)
2. Create code_challenge from SHA256(code_verifier)
3. Redirect to Microsoft with state + code_challenge
4. User authenticates
5. Exchange code + code_verifier for tokens
6. Receive access_token, refresh_token, expires_in
```

## Event Sync

### Pull Events (Outlook → Listopia)

```
1. Query Microsoft Graph: /me/calendars/{calendar_id}/calendarview
2. Filter by date range (±30 days)
3. Map external event ID to local resource
4. Store changeKey for conflict detection
```

### Push Events (Listopia → Outlook)

```
1. Build event object with Microsoft format
   - subject (instead of summary)
   - bodyPreview (instead of description)
   - start.timeZone = "UTC"
2. POST to /me/calendars/{calendar_id}/events
3. Receive event ID and changeKey
4. Create mapping for future syncs
```

## Event Mapping

```ruby
{
  external_id: "outlook_event_id",
  external_type: "outlook_event",
  local_type: "ListItem",
  metadata: {
    calendar_id: "calendar-uuid",
    change_key: "outlook_change_key",
    updated_at: "2024-03-19T..."
  }
}
```

## Error Handling

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| 401 Unauthorized | Token expired | Trigger refresh_token flow |
| 403 Forbidden | Missing permissions | Check scopes in Azure |
| 404 Not Found | Calendar deleted | Prompt user to select calendar |
| 429 Too Many Requests | Rate limited | Implement backoff |

### Rate Limits

Microsoft Graph has different limits than Google:
- 2000 requests per second per tenant
- Backoff-Retry header: wait before retrying

## Testing

```bash
# OAuth service tests
bundle exec rspec spec/services/connectors/microsoft/oauth_service_spec.rb

# Connector tests
bundle exec rspec spec/connectors/microsoft_outlook_spec.rb
```

## Monitoring

```ruby
# View sync history
account.sync_logs.where(operation: "pull_events").recent.limit(10)

# Check errors
account.sync_logs.where(status: "failure")
```

## UI Differences from Google

Both use identical UI (calendar picker + event list), but field names differ:
- Event "subject" displayed same way as Google "summary"
- "bodyPreview" shown as description
- Reminder indicator instead of status

## Future Enhancements

1. **Microsoft 365 Groups:** Sync team calendars
2. **Change Notifications:** Real-time updates via webhooks
3. **Attendees:** Sync meeting attendees and invites
4. **Availability:** Check calendar free/busy status
5. **Categories:** Sync Outlook color categories

## Related Documentation

- `CONNECTORS_OAUTH.md` - OAuth 2.0 patterns
- `CONNECTORS_SECURITY.md` - Token encryption
- `CONNECTORS_GOOGLE_CALENDAR.md` - Detailed implementation patterns (applies to Outlook too)
