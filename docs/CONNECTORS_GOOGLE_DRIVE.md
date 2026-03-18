# Google Drive Connector Implementation

## Overview

The Google Drive connector enables read-only file browsing and attachment of files from Google Drive to Listopia list items. Users can search for files, view metadata, and reference Drive files within their lists.

## Architecture

### Components

#### 1. **GoogleDrive Connector** (`lib/connectors/google_drive.rb`)
- Manifest defining connector metadata
- OAuth scopes for Drive read-only access
- Settings schema (currently minimal - read-only)
- Operations: test_connection, pull (skipped), push (skipped)

#### 2. **OAuth Service** (`app/services/connectors/google/oauth_service.rb`)
- Reuses Google OAuth 2.0 from Phase 3
- Authorization URL generation
- Code exchange for access/refresh tokens
- Token refresh with automatic expiration tracking
- ID token parsing for user identification

#### 3. **File Service** (`app/services/connectors/google/file_service.rb`)
- Fetch user/account information (about)
- List files with pagination
- Search files by name/query
- Fetch individual file metadata
- Generate download URLs
- Export Docs/Sheets/Slides to different formats
- Sync logging for audit trail

#### 4. **Controller** (`app/controllers/connectors/storage/google_drive/files_controller.rb`)
- FilesController: Browse files, view details

#### 5. **Views** (`app/views/connectors/storage/google_drive/`)
- `files/index.html.erb` - File browser with search and pagination
- `files/show.html.erb` - File details with metadata and actions

## Setup & Configuration

### 1. Google Cloud Setup

```bash
# Use existing Google Calendar OAuth app from Phase 3
# The same app/credentials can be reused
# Just ensure the app has Drive API enabled:

# In Google Cloud Console:
# 1. Go to APIs & Services → Library
# 2. Search for "Google Drive API"
# 3. Click "Enable"
```

### 2. Update OAuth Scopes

The existing Google Calendar OAuth app needs an additional scope:

```yaml
# config/credentials.yml.enc
# No changes needed - reuse existing google_calendar credentials
google_calendar:
  client_id: "xxx-yyy-zzz.apps.googleusercontent.com"
  client_secret: "GOCSPX-xxx-yyy-zzz"
```

The Drive scope is configured in the connector manifest, not in credentials.

### 3. Reuse Existing OAuth Flow

Since Google Drive uses the same OAuth provider (Google), users can:
1. Connect to Google Calendar first (Phase 3)
2. Use the same Connected Account to browse Drive files
3. Or connect directly if they haven't connected Google Calendar yet

The system detects the Google provider and reuses the access token.

## OAuth Flow

### Authorization (Same as Google Calendar)

```
1. User clicks "Connect Google Drive"
   ↓
2. App generates state token, stores in session
   ↓
3. Redirect to Google OAuth URL with Drive scope
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
```

### Token Reuse

If user already has a Google Calendar connected:
- Can browse Drive files using the same access token
- Both Calendar and Drive share the same token
- Token refresh applies to both connectors

## File Browsing

### List Files

```
1. Fetch file list from Google Drive API (/files endpoint)
   ↓
2. Apply search query if provided
   ↓
3. Return paginated results (50 files per page)
   ↓
4. Log operation with record count
```

### File Search

```
Query Format:
- Filename search: "report" → finds "quarterly_report.pdf", "report.docx"
- Trashed filter: Always excludes trashed files
- Ordering: By modified time (newest first)
```

### Pagination

```
- Page size: 50 files
- Next token: Provided by API for loading more
- UI: "Load More" button for lazy loading
```

## File Metadata

Displayed for each file:
- **Name** - File name with icon (📄 Doc, 📊 Sheet, 📽️ Presentation, 📁 Folder, etc.)
- **Type** - MIME type as a badge
- **Size** - Human-readable size (1.2 MB, 450 KB, etc.)
- **Modified** - Time since last modification
- **Actions** - Open in Drive, View details

### Detailed View

Additional metadata shown on file details page:
- File ID (copyable)
- MIME type (full)
- File size (detailed)
- Last modified timestamp
- Owner name
- Parent folder ID

## Integration with List Items

### Attaching Files

Future enhancement: Attach Drive files to list items via:
```ruby
ListItem.attachments.create!(
  external_id: file_id,
  external_type: "google_drive_file",
  external_url: webViewLink,
  metadata: {
    name: file_name,
    mimeType: mime_type,
    size: file_size
  }
)
```

### File References

Users can reference files by:
- Copying file ID from details page
- Embedding in list item description
- Attaching via UI (future)

## API Limits

Google Drive API has these quotas:
- 10 million tokens per day per user
- 100 concurrent connections per user
- File list: 50 files per request

To avoid hitting limits:
- Implement caching for file lists (15 minutes)
- Use incremental sync with pageToken
- Search for specific files rather than listing all

## Error Handling

### Token Errors
```
- Token expired → Refresh automatically
- Refresh failed → Mark account as :errored
- Invalid scope → User needs to reconnect
```

### API Errors
```
- 401 Unauthorized → Token likely invalid, trigger refresh
- 403 Forbidden → Insufficient scopes
- 404 Not Found → File doesn't exist or was deleted
- 429 Too Many Requests → Rate limited, retry with backoff
- 500 Server Error → Google API error, retry later
```

## Monitoring & Debugging

### Sync Logs

```ruby
# View file operations
connector_account.sync_logs.where(operation: "list_files").recent

# Check for errors
connector_account.sync_logs.where(status: "failure")

# Measure performance
log = connector_account.sync_logs.recent.first
duration_seconds = log.duration_ms / 1000.0
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "404 File not found" | File deleted or moved | Search for file again |
| "403 Forbidden" | Missing Drive scope | Disconnect and reconnect |
| "Files not loading" | Slow API or connection | Wait and retry |
| Empty file list | No files in Drive or insufficient access | Create files in Drive |
| Token expired | Token not refreshed in time | Reconnect via OAuth |

## Testing

### Unit Tests
```bash
bundle exec rspec spec/services/connectors/google/file_service_spec.rb
bundle exec rspec spec/connectors/google_drive_spec.rb
```

### Integration Tests
```bash
bundle exec rspec spec/integration/connectors/google_drive_spec.rb
```

### Manual Testing

```ruby
# Create test account
user = User.find(1)
org = user.organizations.first

account = Connectors::Account.create!(
  user: user,
  organization: org,
  provider: "google_drive",
  provider_uid: "user@gmail.com",
  access_token: "test_token",
  token_expires_at: 1.hour.from_now
)

# Test file fetch
service = Connectors::Google::FileService.new(connector_account: account)
files_data = service.list_files

# Test specific file
file = service.get_file("file_id_here")

# Test about info
about = service.fetch_about
```

## Future Enhancements

### Phase 1: Enhanced File Browsing
- Folder navigation (browse folder hierarchy)
- File sorting (by name, size, modified date)
- File type filtering (only images, only documents, etc.)
- Star/favorite files

### Phase 2: File Attachment
- Drag-and-drop to attach files to items
- Embedded file preview in list items
- File metadata in item details
- Download file from list view

### Phase 3: Bidirectional Sync
- Create files in Drive from list items
- Update file metadata from Listopia
- Two-way sync of comments
- Attachment tracking

### Phase 4: Export & Sharing
- Export list as Google Doc
- Share list with Drive collaborators
- Generate reports as PDF
- Archive lists to Drive

### Phase 5: Advanced Integration
- Sync folder contents automatically
- Watch for changes via push notifications
- OCR text extraction from Drive files
- Version history and rollback

## Configuration Precedence

The connector uses this precedence for API key:
1. `Rails.application.credentials.dig(:google_calendar, :api_key)`
2. `ENV["GOOGLE_API_KEY"]`
3. Raises error if neither found

## Related Documentation

- `CONNECTORS_OAUTH.md` - OAuth 2.0 implementation details
- `CONNECTORS_GOOGLE_CALENDAR.md` - Google integration setup and patterns
- `CONNECTORS_SECURITY.md` - Token encryption and authorization
- `CONNECTORS_ARCHITECTURE_PLAN.md` - Overall connector architecture
