# Google Calendar Connector Implementation

## Overview

The Google Calendar connector enables bidirectional event sync between Listopia and Google Calendar. Users can view, create, and update events through the Listopia interface with automatic synchronization to their Google Calendar.

## Architecture

### Components

#### 1. **GoogleCalendar Connector** (`app/connectors/google_calendar.rb`)
- Manifest defining connector metadata
- OAuth scopes for Calendar API access
- Settings schema (default calendar, sync direction)
- Operations: test_connection, pull, push

#### 2. **OAuth Service** (`app/services/connectors/google/oauth_service.rb`)
- Google OAuth 2.0 implementation
- Authorization URL generation with PKCE (when applicable)
- Code exchange for access/refresh tokens
- Token refresh with automatic expiration tracking
- ID token parsing for user identification

#### 3. **Calendar Fetch Service** (`app/services/connectors/google/calendar_fetch_service.rb`)
- List user's accessible calendars
- Fetch individual calendar metadata
- Error handling and retry logic
- Sync logging for audit trail

#### 4. **Event Sync Service** (`app/services/connectors/google/event_sync_service.rb`)
- Pull events from Google Calendar (with time window)
- Push Listopia items to Google Calendar
- Event mapping (external ID ↔ local ID)
- ETag tracking for conflict detection
- Timezone handling

#### 5. **Sync Job** (`app/jobs/connectors/calendars/google/sync_job.rb`)
- Background event synchronization
- Proactive refresh on schedule
- Error state tracking
- Current context setup for authorization

#### 6. **Controllers** (`app/controllers/connectors/calendars/google/`)
- CalendarsController: Select which calendar to sync
- EventsController: View synced events, trigger manual sync

## Setup & Configuration

### 1. Google Cloud Setup

```bash
# Create Google Cloud project
# Enable Calendar API and Drive API
# Create OAuth 2.0 credentials (Web application)
# Authorized redirect URIs: https://yourdomain.com/connectors/oauth/google_calendar/callback
```

### 2. Store Credentials

```yaml
# config/credentials.yml.enc
google_calendar:
  client_id: "xxx-yyy-zzz.apps.googleusercontent.com"
  client_secret: "GOCSPX-xxx-yyy-zzz"
```

Or use environment variables:
```bash
GOOGLE_OAUTH_CLIENT_ID=xxx-yyy-zzz.apps.googleusercontent.com
GOOGLE_OAUTH_CLIENT_SECRET=GOCSPX-xxx-yyy-zzz
```

### 3. Schedule Sync Job

```ruby
# config/schedule.yml (using whenever gem)
every 1.hour do
  runner "Connectors::Account.where(provider: 'google_calendar', status: 'active').find_each { |a| Connectors::Calendars::Google::SyncJob.perform_later(connector_account_id: a.id) }"
end
```

## OAuth Flow

### Authorization

```
1. User clicks "Connect Google Calendar"
   ↓
2. App generates state token, stores in session
   ↓
3. Redirect to Google OAuth URL with state parameter
   ↓
4. User authenticates and approves scopes
   ↓
5. Google redirects back with authorization code + state
   ↓
6. App validates state (CSRF protection)
   ↓
7. Exchange code for tokens (access_token, refresh_token, expires_in)
   ↓
8. Decrypt and store tokens in connector_accounts
   ↓
9. Extract user info from ID token JWT
   ↓
10. User selects which calendar to sync
```

### Token Refresh

```
1. Check if token_expires_at < 1 hour from now
   ↓
2. If expired, call refresh_token endpoint with refresh_token
   ↓
3. Receive new access_token and new expiration
   ↓
4. Update connector_account with new tokens
   ↓
5. Clear error state if refresh successful
```

## Event Sync

### Pull Events (Google → Listopia)

```
1. Fetch calendar ID from settings (user's selected calendar)
2. Query Google Calendar API for events (±30 days)
3. For each event:
   - Check if mapping exists (external_id → local_id)
   - Create new mapping if first sync
   - Update ETag for conflict detection
4. Log operation with record counts
```

### Push Events (Listopia → Listopia as Google Events)

```
1. Build Google Calendar event object from Listopia item
   - Title → summary
   - Description → description
   - Dates → start/end times
2. POST to Google Calendar API
3. Receive event ID from Google
4. Create event mapping with external_id = Google event ID
5. Log operation with record counts
```

## Event Mapping

Maps external Google Calendar events to local Listopia items:

```ruby
# connector_event_mappings table
{
  external_id: "google_event_id_123",
  external_type: "google_calendar_event",
  local_type: "ListItem",
  local_id: "listopia_item_uuid",
  sync_direction: "both",
  external_etag: "etag_from_google",
  metadata: {
    calendar_id: "user@gmail.com",
    updated_at: "2024-03-19T..."
  }
}
```

## Settings Schema

### default_calendar_id
- **Type:** Select
- **Options:** Fetched from user's Google Calendars
- **Purpose:** Which calendar to sync with
- **Required:** Yes

### sync_direction
- **Type:** Select
- **Options:** `["pull", "push", "both"]`
- **Default:** `"both"`
- **Purpose:** Direction of event synchronization

### auto_sync
- **Type:** Boolean
- **Default:** `true`
- **Purpose:** Enable automatic sync on schedule

## Error Handling

### Token Errors
```
- Token expired → Refresh automatically
- Refresh failed → Mark account as :errored
- Invalid scope → Clear account, notify user
```

### API Errors
```
- 401 Unauthorized → Token likely invalid, trigger refresh
- 403 Forbidden → Insufficient scopes
- 404 Not Found → Event deleted in Google Calendar
- 429 Too Many Requests → Rate limited, retry with backoff
```

### Conflict Resolution
```
- Check external_etag before updating
- If different, Google event was modified elsewhere
- Use merge/conflict resolution strategy
- Default: Google wins (authoritative source)
```

## Monitoring & Debugging

### Sync Logs

```ruby
# View sync history for a calendar
connector_account.sync_logs.where(operation: "pull_events").recent.limit(10)

# Check for errors
connector_account.sync_logs.where(status: "failure")

# Measure performance
log = connector_account.sync_logs.recent.first
duration_seconds = log.duration_ms / 1000.0
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| 401 Unauthorized | Token expired, no refresh_token | Disconnect and reconnect |
| 403 Forbidden | Missing Calendar API scope | Check credentials.yml.enc scopes |
| Events not syncing | auto_sync disabled or job not running | Check job schedule, enable auto_sync |
| Duplicate events | Push happens twice | Check idempotency of push operation |
| Timezone confusion | Client vs server timezone | Use ISO 8601 with timezone info |

## Testing

### Unit Tests
```bash
bundle exec rspec spec/services/connectors/google/oauth_service_spec.rb
bundle exec rspec spec/services/connectors/google/calendar_fetch_service_spec.rb
bundle exec rspec spec/services/connectors/google/event_sync_service_spec.rb
bundle exec rspec spec/connectors/google_calendar_spec.rb
```

### Integration Tests
```bash
bundle exec rspec spec/integration/connectors/google_calendar_spec.rb
```

### Manual Testing

```ruby
# Test OAuth flow
user = User.find(1)
org = user.organizations.first

# Simulate callback
account = Connectors::Account.create!(
  user: user,
  organization: org,
  provider: "google_calendar",
  provider_uid: "user@gmail.com",
  access_token: "test_token",
  token_expires_at: 1.hour.from_now
)

# Test calendar fetch
service = Connectors::Google::CalendarFetchService.new(connector_account: account)
calendars = service.fetch_calendars

# Test event sync
sync_service = Connectors::Google::EventSyncService.new(connector_account: account)
events = sync_service.pull_events
```

## Rate Limiting

Google Calendar API has these quotas:
- 10 requests per second per user
- 1 million requests per day per project

To avoid hitting limits:
- Batch event fetches (query ±30 days, not all history)
- Cache calendar list for 1 hour
- Use sync tokens for incremental sync (future enhancement)
- Implement exponential backoff for 429 responses

## Future Enhancements

1. **Push Notifications:** Subscribe to Google Calendar push notifications for real-time sync
2. **Sync Tokens:** Use sync tokens for incremental event sync (more efficient)
3. **Attendee Sync:** Sync attendees and RSVP status
4. **Timezone Handling:** Better timezone-aware event creation
5. **Recurring Events:** Handle recurring event series properly
6. **Attachments:** Sync attachments between Google Calendar and Listopia
7. **Event Search:** Full-text search across synced events

## Related Documentation

- `CONNECTORS_OAUTH.md` - OAuth 2.0 implementation details
- `CONNECTORS_SECURITY.md` - Token encryption and authorization
- `CONNECTORS_ARCHITECTURE_PLAN.md` - Overall connector architecture
