# Audit & Compliance System

Listopia includes a comprehensive audit and compliance system combining Logidze (version history) with Event tracking (actor information) to provide complete "who changed what when" tracking for regulatory compliance.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Admin Audit Dashboard                                   │
│ (/admin/audit)                                          │
└──────────────────────┬──────────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
   ┌─────────┐  ┌──────────┐  ┌──────────────┐
   │ Events  │  │AuditTrail│  │Compliance    │
   │(Actor)  │  │(Combined)│  │Report        │
   └────┬────┘  └────┬─────┘  └──────┬───────┘
        │            │               │
        │            └───────┬───────┘
        │                    │
        └────────┬───────────┘
                 ▼
      ┌──────────────────────┐
      │ Logidze Versions     │
      │ (Full Snapshots)     │
      └──────────────────────┘
```

## Core Components

### 1. Event Model (Actor Tracking)
Stores "who" made each change with organization scoping.

```ruby
# Create events automatically (via ListItem callbacks)
Event.emit("list_item.created", org_id, user_id, {item_id: 123, title: "..."})

# Query by type
Event.where(organization_id: org.id).by_type("list_item.updated")

# Query by user
Event.where(organization_id: org.id).by_actor(user)

# Query by date range
Event.where(organization_id: org.id).since(30.days.ago)
```

### 2. Logidze Versions (Full History)
Built-in version snapshots stored in the model itself.

```ruby
# Access version history
list_item.logidze_versions

# Get specific version
list_item.logidze_at(Time.current - 1.day)

# See all changes to a field
list_item.logidze_versions.map { |v| v.changes["status"] }
```

### 3. AuditTrail Service (Combined View)
Unifies Event + Logidze data to show "who changed what".

```ruby
# Create audit trail for a resource
audit = AuditTrail.new(list_item, organization_id)

# Get unified entries with actor info
audit.entries  # => [{timestamp, actor, changes, version, ...}]

# Get field change history
audit.field_history("status")  # => [{timestamp, actor, from, to}, ...]

# Export as JSON
audit.to_json
```

### 4. ComplianceReport Service (Regulatory)
Generates compliance reports with risk assessment.

```ruby
# Create report for date range
report = ComplianceReport.new(
  organization,
  events,
  { start_date: 90.days.ago, end_date: Time.current }
)

# Get summaries
report.summary              # => {total_events, unique_users, ...}
report.sensitive_changes    # => Access/ownership/status changes
report.critical_actions     # => Deletions, completions
report.risk_assessment      # => Anomalies, bulk operations

# Export
report.to_csv     # => CSV file
report.to_json    # => JSON API
report.to_html    # => Dashboard HTML
```

## Admin Dashboard Routes

All routes require admin authentication and are organization-scoped.

### Dashboard (`/admin/audit`)
Overview of recent changes and summaries.

```ruby
GET /admin/audit
GET /admin/audit?organization_id=:id&days=30
```

Provides:
- Summary statistics
- Sensitive changes in date range
- Recent events
- Risk assessment

### Compliance Report (`/admin/audit/compliance_report`)
Detailed compliance report with export.

```ruby
GET /admin/audit/compliance_report?organization_id=:id&days=90
GET /admin/audit/compliance_report?format=csv
GET /admin/audit/compliance_report?format=json
```

Provides:
- Who changed what when
- Sensitive field tracking
- Critical action audit trail
- Risk assessment
- Export in CSV/JSON

### User Activity (`/admin/audit/activity_log`)
Track individual user actions.

```ruby
GET /admin/audit/activity_log?organization_id=:id&user_id=:uid&days=30
GET /admin/audit/activity_log?format=csv
```

Provides:
- All actions by user
- Event timeline
- Change summary
- CSV export

### Resource Audit Trail (`/admin/audit/audit_trail`)
Full history of changes to a specific resource.

```ruby
GET /admin/audit/audit_trail?resource_type=ListItem&resource_id=:id
GET /admin/audit/audit_trail?resource_type=List&resource_id=:id
```

Provides:
- Version history with actors
- Field-by-field change log
- Full snapshots
- Timeline

### Export (`/admin/audit/export_audit`)
Bulk export audit data.

```ruby
GET /admin/audit/export_audit?days=90&format=csv
GET /admin/audit/export_audit?format=json
```

## Using Audit Helpers in Views

Include the audit helper in views or other helpers:

```ruby
# In a helper or view:
include Admin::AuditHelper

# Get audit trail for a resource
audit = audit_trail_for(list_item, current_organization)

# Get organization events
events = organization_events(current_organization, event_type: "list_item.updated")

# Get compliance report
report = compliance_report(current_organization, start_date: 30.days.ago)
```

## Query Patterns

### All changes by user in org
```ruby
Event.where(organization_id: org.id).by_actor(user).recent
```

### Sensitive field changes (access control, status, ownership)
```ruby
helper.sensitive_changes_log(organization, days = 30)
```

### Critical actions (deletions, completions)
```ruby
report.critical_actions
```

### Activity summary for date range
```ruby
helper.audit_summary(organization, 30.days.ago, Time.current)
```

### Export audit for compliance
```ruby
csv = helper.export_audit_trail_csv(organization, days = 90)
# Send to external system, download, etc.
```

## Sensitive Fields Tracked

Fields flagged as sensitive in compliance reports:
- `status` - Item/list status changes
- `priority` - Priority escalations
- `assigned_user_id` - Task assignments
- `access` - Permission changes
- `is_public` - Visibility changes
- `owner_id` - Ownership transfers

## Risk Assessment

The system flags several risk conditions:

### High Risk
- **Bulk deletions**: 10+ items deleted in short period
- **Access changes**: Unauthorized permission modifications
- **Ownership changes**: Unusual ownership transfers

### Anomalies Detected
- High-volume activity from single user in short period
- Rapid deletions (5+ in 1 hour)
- Unusual access patterns

## Compliance Export Example

```ruby
# Weekly compliance check
org = Organization.find(id)
report = ComplianceReport.new(
  org,
  Event.where(organization_id: org.id).since(7.days.ago),
  { include_sensitive: true }
)

# Send to compliance system
upload_to_compliance_system(
  report.to_csv,
  filename: "listopia_audit_#{Time.current.to_date}.csv"
)

# Check for anomalies
if report.risk_assessment[:anomalies].any?
  send_alert_to_security_team(report.risk_assessment)
end
```

## Implementation Details

### Organization Scoping
All queries are automatically scoped to `organization_id` preventing cross-org data leaks.

### Multi-Tenant Safety
- Event model requires `organization_id`
- AuditTrail service validates org ownership
- Helper methods filter by current organization

### Performance
- Event table indexed on: `event_type`, `organization_id`, `actor_id`, `created_at`
- Logidze queries use PostgreSQL JSONB optimization
- Batch exports use streaming for large datasets

### Retention
- Events retained indefinitely (audit trail requirement)
- Logidze history kept with main records
- Consider archiving old events if table grows > 1M rows

## Future Enhancements

1. **Event Streaming**: Kafka/Pub-Sub for real-time compliance alerts
2. **Webhooks**: Send events to external compliance systems
3. **Machine Learning**: Anomaly detection for unusual patterns
4. **Encryption**: Store sensitive field values encrypted in event_data
5. **Archival**: Move old events to separate storage for cost optimization
