# Event System

Listopia uses a lightweight event-driven architecture to decouple integrations from core app logic and maintain a complete audit trail.

## Overview

The event system consists of two complementary mechanisms:

1. **ActiveSupport::Notifications** - Real-time pub/sub for immediate processing
2. **Event Model** - Persistent audit log for compliance and historical analysis

## Architecture

```
┌─────────────────┐
│   ListItem      │
│   (Model)       │
└────────┬────────┘
         │ after_update
         │
         ├─→ Emit Event (ActiveSupport::Notifications)
         │   └─→ Real-time subscribers (Slack, Calendar, etc.)
         │
         └─→ Create Event record (Event model)
             └─→ Audit trail (queryable history)
```

## Available Events

### List Item Events

| Event | Triggered | Payload |
|-------|-----------|---------|
| `list_item.created` | When item is created | `item`, `user_id` |
| `list_item.updated` | When item fields change | `item`, `user_id`, `changes` |
| `list_item.status_changed` | When status changes (pending→in_progress→completed) | `item`, `user_id`, `previous_status`, `new_status` |
| `list_item.completed` | When item is marked complete | `item`, `user_id`, `completed_at` |
| `list_item.assigned` | When assigned to a user | `item`, `user_id`, `assigned_to` |
| `list_item.priority_changed` | When priority changes to high/urgent | `item`, `user_id`, `previous_priority`, `new_priority` |
| `list_item.deleted` | When item is destroyed | `item`, `user_id` |

## Using the Event System

### 1. Real-Time Subscribers (ActiveSupport::Notifications)

Subscribe to events in `config/initializers/event_subscriptions.rb`:

```ruby
# Notify Slack when item is completed
ActiveSupport::Notifications.subscribe("list_item.completed") do |name, start, finish, id, payload|
  item = payload[:item]
  user = payload[:user_id]

  SlackNotificationService.notify(
    channel: item.list.slack_channel,
    message: "✅ #{item.title} completed by #{user.name}"
  )
end

# Sync to external calendar when item is created
ActiveSupport::Notifications.subscribe("list_item.created") do |name, start, finish, id, payload|
  item = payload[:item]
  CalendarSyncService.enqueue_sync(item)
end
```

Or inherit from `EventSubscriber` for organized integration code:

```ruby
# app/services/integrations/slack_integration.rb
class Integrations::SlackIntegration < EventSubscriber
  def initialize
    super
    subscribe_to("list_item.completed") { |payload| notify_completion(payload) }
    subscribe_to("list_item.assigned") { |payload| notify_assignment(payload) }
  end

  private

  def notify_completion(payload)
    item = payload[:item]
    SlackClient.message(
      channel: item.list.slack_channel,
      text: "Completed: #{item.title}"
    )
  end

  def notify_assignment(payload)
    item = payload[:item]
    assigned_to = payload[:assigned_to]
    SlackClient.message(
      channel: assigned_to.slack_username,
      text: "You've been assigned: #{item.title}"
    )
  end
end

# config/initializers/event_subscriptions.rb
Integrations::SlackIntegration.new  # Initialize to set up subscriptions
```

### 2. Audit Trail (Event Model)

Query the audit log to understand what happened:

```ruby
# Get all events for an organization
Event.where(organization_id: org.id).recent

# Find what changed to a specific item
Event.where(organization_id: org.id)
     .by_type("list_item.updated")
     .by_actor(user)
     .since(1.week.ago)

# Rebuild state from events
completed_events = Event.by_type("list_item.completed").since(1.day.ago)
completed_items = completed_events.map { |e| ListItem.find(e.event_data["item_id"]) }
```

## When to Use Each Mechanism

| Use Case | Mechanism | Reason |
|----------|-----------|--------|
| Slack/Calendar notifications | ActiveSupport::Notifications | Real-time, no DB overhead |
| Compliance audit log | Event model | Persistent, queryable |
| Integration reconciliation | Event model | Can replay to rebuild state |
| Quick-and-dirty subscriber | ActiveSupport::Notifications | Simple, built-in |
| Production-grade integration | EventSubscriber + Event model | Both audit + action |

## Event Emission

Events are emitted automatically when items change. The emission happens in `ListItem` model callbacks:

```ruby
# app/models/list_item.rb
after_commit :notify_item_created, on: :create
after_commit :notify_item_updated, on: :update
after_commit :notify_item_completed, on: :update, if: :completion_changed?
```

### Manually Emitting Events

If you need to emit custom events:

```ruby
# Using Event.emit helper
Event.emit(
  "custom.event_type",
  organization_id,
  actor_id,
  { custom_data: "value" }
)

# Using ActiveSupport::Notifications
ActiveSupport::Notifications.instrument(
  "custom.event_type",
  item: item,
  user_id: user.id,
  custom_field: value
)
```

## Best Practices

1. **Always include organization_id** in events for multi-tenant safety
2. **Keep event_data minimal** - store only what's needed for integration
3. **Use consistent event names** - `domain.action` format (e.g., `list_item.completed`)
4. **Handle missing data gracefully** - subscriptions should handle missing items
5. **Don't block on subscribers** - notifications are async where possible
6. **Log failures** - subscribers should catch and log errors

## Integration Examples

### Slack Notification on Completion

```ruby
# config/initializers/event_subscriptions.rb
ActiveSupport::Notifications.subscribe("list_item.completed") do |name, start, finish, id, payload|
  item = payload[:item]
  user_id = payload[:user_id]

  begin
    connector = item.list.organization
                    .connector_accounts
                    .find_by(provider: "slack")
    next unless connector&.active?

    SlackNotificationJob.perform_later(
      item_id: item.id,
      connector_account_id: connector.id
    )
  rescue => e
    Rails.logger.error("Slack notification failed: #{e.message}")
  end
end
```

### Calendar Sync on Item Creation

```ruby
# config/initializers/event_subscriptions.rb
ActiveSupport::Notifications.subscribe("list_item.created") do |name, start, finish, id, payload|
  item = payload[:item]

  begin
    connectors = item.list.organization
                     .connector_accounts
                     .where(provider: ["google_calendar", "microsoft_calendar"])

    connectors.each do |connector|
      CalendarEventCreationJob.perform_later(
        item_id: item.id,
        connector_account_id: connector.id
      )
    end
  rescue => e
    Rails.logger.error("Calendar sync failed: #{e.message}")
  end
end
```

### Audit Trail Query for Compliance

```ruby
# Find all changes to sensitive fields in the past 90 days
sensitive_events = Event.where(organization_id: org.id)
                         .by_type("list_item.updated")
                         .since(90.days.ago)
                         .select do |event|
                           event.event_data["changes"]&.keys&.any? { |k| k.in?(%w[status priority assigned_user_id]) }
                         end

sensitive_events.each do |event|
  puts "#{event.actor.name} changed #{event.event_data['item_id']} on #{event.created_at}"
end
```

## Migration Path

If you're adding events to an existing feature:

1. **Add event emissions** to the model callbacks
2. **Create subscribers** in `config/initializers/event_subscriptions.rb`
3. **Test** with a simple integration first (Slack notification)
4. **Monitor** events table to ensure data consistency
5. **When ready for rails_event_store**: Use events as migration source
