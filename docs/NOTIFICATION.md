# Listopia Notification System Documentation

## Supported Notification Scenarios

### **List Collaboration Scenarios**
1. **User receives invitation to collaborate** - When someone invites them to a list
2. **User is removed from collaboration** - When they're removed from a list they were collaborating on
3. **Invitation acceptance notification** - List owner notified when invitation is accepted
4. **Invitation rejection notification** - List owner notified when invitation is declined

### **List Activity Scenarios**
5. **List title/description changes** - Collaborators notified when list content is updated (excluding the person making the change)
6. **List status changes** - Collaborators notified when list status changes (draft → active → completed → archived, excluding the person making the change)

### **Item Activity Scenarios**  
7. **Item added to list** - Collaborators notified when new items are created (excluding the person adding the item)
8. **Item modified in list** - Collaborators notified when items are updated (excluding the person making the change)
9. **Item deleted from list** - Collaborators notified when items are removed (excluding the person deleting the item)

### **Notification Preferences**
- All scenarios respect individual user notification preferences
- Users can control delivery channels (email, SMS, push)
- Users can control notification types (collaboration, list activity, item activity, status changes)
- Users can set frequency (immediate, daily digest, weekly digest, disabled)

## Overview

Listopia uses the **Noticed gem** with custom notification preferences to provide users with real-time updates about list activities, collaborations, and status changes. The system respects user preferences and supports multiple delivery channels.

## Architecture

### Core Components

1. **Noticed Gem** - Handles notification delivery and storage
2. **NotificationSetting Model** - Stores user preferences
3. **ApplicationNotifier** - Base class for all notifications
4. **Model Callbacks** - Automatic notification triggers
5. **Controller Actions** - Manual notification triggers for user actions

## When to Use Models vs Controllers

### **Use Model Callbacks** ✅ (Primary Strategy)

**When to use:**
- Automatic notifications when data changes
- Business logic that should trigger regardless of how the change occurs
- Consistent behavior across console, API, web interface, background jobs

**Examples:**
- List title/description changes
- List status changes (draft → active → completed)
- Item creation/updates/deletion
- Collaboration creation/removal

**Benefits:**
- Consistency - notifications fire regardless of entry point
- Single responsibility - models handle business logic
- DRY principle - no duplication across controllers
- Testability - easier to test in isolation

```ruby
# app/models/list.rb
class List < ApplicationRecord
  after_commit :notify_title_change, on: :update, if: :saved_change_to_title?
  after_commit :notify_status_change, on: :update, if: :saved_change_to_status?

  private

  def notify_title_change
    return unless Current.user
    recipients = collaborators.where.not(id: Current.user.id)
    ListTitleChangedNotifier.with(actor_id: Current.user.id, list_id: id)
                           .deliver_to_enabled_users(recipients)
  end
end
```

### **Use Controller Actions** ⚠️ (Limited Cases)

**When to use:**
- Explicit user actions that don't map to model changes
- Complex multi-step operations
- When you need additional context beyond model data

**Examples:**
- Invitation acceptance/rejection responses
- Bulk operations
- User-initiated sharing actions

```ruby
# app/controllers/collaborations_controller.rb
def accept_invitation
  @collaboration.update!(status: 'accepted')
  
  # Notify the list owner about acceptance
  InvitationAcceptedNotifier.with(
    actor_id: current_user.id,
    list_id: @collaboration.list_id
  ).deliver_to_enabled_users([@collaboration.list.owner])
end
```

## Notification Types & Configuration

### Notification Categories

| Category | Description | User Setting |
|----------|-------------|--------------|
| `collaboration` | Invitations, user additions/removals | `collaboration_notifications` |
| `list_activity` | Title, description changes | `list_activity_notifications` |
| `item_activity` | Item creation, updates, deletion | `item_activity_notifications` |
| `status_change` | List status transitions | `status_change_notifications` |

### Delivery Channels

| Channel | Description | User Setting |
|---------|-------------|--------------|
| Database | Always enabled (for in-app notifications) | N/A |
| Email | Email notifications | `email_notifications` |
| SMS | Text message notifications | `sms_notifications` |
| Push | Browser/mobile push notifications | `push_notifications` |

### Frequency Options

| Frequency | Description | Behavior |
|-----------|-------------|----------|
| `immediate` | Send notifications right away | Respects quiet hours |
| `daily_digest` | Bundle into daily summary | Sent once per day |
| `weekly_digest` | Bundle into weekly summary | Sent once per week |
| `disabled` | No notifications | User receives no notifications |

## Creating Notifiers

### Basic Notifier Structure

```ruby
# app/notifiers/example_notifier.rb
class ExampleNotifier < ApplicationNotifier
  # Required: Define notification type for user preferences
  def notification_type
    "collaboration"  # or "list_activity", "item_activity", "status_change"
  end

  # Required: Notification title
  def title
    "Short descriptive title"
  end

  # Required: Notification message
  def message
    "#{actor_name} performed an action on #{target_list&.title}"
  end

  # Optional: Custom icon
  def icon
    "user-plus"  # Lucide icon name
  end

  # Optional: Custom URL
  def url
    Rails.application.routes.url_helpers.list_path(target_list)
  end
end
```

### Using Notifier Parameters

Access parameters passed via `.with()`:

```ruby
class ListStatusChangedNotifier < ApplicationNotifier
  def notification_type
    "status_change"
  end

  def title
    "List status changed to #{params[:new_status]}"
  end

  def message
    "#{actor_name} changed \"#{target_list&.title}\" from #{params[:previous_status]} to #{params[:new_status]}"
  end

  def icon
    case params[:new_status]
    when "active" then "play"
    when "completed" then "check-circle"
    when "archived" then "archive"
    else "circle"
    end
  end
end
```

## Model Implementation Patterns

### Callback Timing Guide

| Callback | Use Case | Example |
|----------|----------|---------|
| `after_commit :method, on: :create` | Object creation | New item added |
| `after_commit :method, on: :update, if: :condition` | Specific field changes | Title updated |
| `before_destroy :method` | Object deletion | Item deleted (need object data) |

### Conditional Callbacks

Use Rails' built-in change detection:

```ruby
class List < ApplicationRecord
  # Only notify when title OR description changes
  after_commit :notify_content_change, on: :update, if: :title_or_description_changed?

  private

  def title_or_description_changed?
    saved_change_to_title? || saved_change_to_description?
  end

  def notify_content_change
    return unless Current.user
    
    recipients = collaborators.where.not(id: Current.user.id)
    return if recipients.empty?

    ListTitleChangedNotifier.with(
      actor_id: Current.user.id,
      list_id: id,
      previous_title: title_before_last_save,
      new_title: title,
      previous_description: description_before_last_save,
      new_description: description
    ).deliver_to_enabled_users(recipients)
  end
end
```

### Recipient Filtering Pattern

Standard pattern for getting notification recipients:

```ruby
def list_notification_recipients
  recipients = []
  
  # Add list owner (unless they're the actor)
  recipients << list.owner unless list.owner.id == Current.user.id
  
  # Add collaborators (except the actor)
  collaborators_to_notify = list.collaborators.where.not(id: Current.user.id)
  recipients.concat(collaborators_to_notify)
  
  recipients.uniq.compact
end
```

## Delivery Methods

### Standard Delivery (Respects Preferences)

```ruby
# Filters recipients based on their notification preferences
NotifierClass.with(params).deliver_to_enabled_users(recipients)
```

### Immediate Delivery (Bypasses Preferences)

```ruby
# Sends to all recipients regardless of preferences (use sparingly)
NotifierClass.with(params).deliver_later(recipients)
```

### Background Delivery

All notifications are delivered via background jobs using Rails' Solid Queue by default.

## User Preference Integration

### Checking User Preferences

```ruby
# Check if user wants this notification type
user.wants_notification?("collaboration")

# Check specific channel
user.wants_notification?("item_activity", :email)

# Check if user wants immediate notifications
user.wants_immediate_notifications?
```

### Setting Up Default Preferences

New users automatically get default notification settings via the User model callback:

```ruby
# app/models/user.rb
class User < ApplicationRecord
  after_create :create_default_notification_settings

  private

  def create_default_notification_settings
    build_notification_settings.save! unless notification_settings
    notification_settings
  end
end
```

## Testing Notifications

### Testing Model Callbacks

```ruby
# spec/models/list_spec.rb
RSpec.describe List, type: :model do
  describe "notification callbacks" do
    let(:user) { create(:user) }
    let(:list) { create(:list, owner: user) }
    let(:collaborator) { create(:user) }

    before do
      Current.user = user
      list.collaborators << collaborator
    end

    it "sends notification when title changes" do
      expect {
        list.update!(title: "New Title")
      }.to have_enqueued_job(Noticed::DeliveryJob)
    end

    it "does not send notification when untracked field changes" do
      expect {
        list.update!(updated_at: Time.current)
      }.not_to have_enqueued_job(Noticed::DeliveryJob)
    end
  end
end
```

### Testing Notifiers

```ruby
# spec/notifiers/list_title_changed_notifier_spec.rb
RSpec.describe ListTitleChangedNotifier do
  let(:user) { create(:user) }
  let(:list) { create(:list) }
  let(:notifier) { described_class.with(actor_id: user.id, list_id: list.id) }

  describe "#notification_type" do
    it "returns list_activity" do
      expect(notifier.notification_type).to eq("list_activity")
    end
  end

  describe "#title" do
    it "includes the list title" do
      expect(notifier.title).to include(list.title)
    end
  end

  describe "#message" do
    it "includes the actor name" do
      expect(notifier.message).to include(user.name)
    end
  end
end
```

## Common Patterns & Best Practices

### 1. Always Check for Current.user

```ruby
def notify_something
  return unless Current.user  # Prevents notifications from console/seeds
  # ... notification logic
end
```

### 2. Filter Out the Actor

```ruby
recipients = list.collaborators.where.not(id: Current.user.id)
```

### 3. Use Conditional Callbacks

```ruby
after_commit :notify_change, on: :update, if: :relevant_change?

def relevant_change?
  saved_change_to_title? || saved_change_to_description?
end
```

### 4. Handle Empty Recipients

```ruby
def notify_collaborators
  recipients = get_recipients
  return if recipients.empty?  # Don't create notifications with no recipients
  
  NotifierClass.with(params).deliver_to_enabled_users(recipients)
end
```

### 5. Use before_destroy for Deletion Notifications

```ruby
# ✅ Correct - object still exists
before_destroy :notify_deletion

# ❌ Wrong - object is already deleted
after_commit :notify_deletion, on: :destroy
```

## Troubleshooting

### Common Issues

**1. Notifications not sending**
- Check if `Current.user` is set
- Verify recipients exist and want notifications
- Check notification type matches user preferences

**2. Missing object data in destroy notifications**
- Use `before_destroy` instead of `after_destroy`
- Capture necessary data before destruction

**3. Infinite notification loops**
- Ensure actor is excluded from recipients
- Use conditional callbacks to prevent unnecessary triggers

**4. Missing Current.user context**
- Add `Current.user = current_user` in ApplicationController
- Check that authentication sets Current.user

### Debugging Commands

```ruby
# Check user notification preferences
user.notification_preferences

# Check if user wants specific notification
user.wants_notification?("collaboration")

# View recent notifications
user.notifications.recent.includes(:event)

# Check notification queue
Noticed::DeliveryJob.queue_adapter.enqueued_jobs
```

## Future Enhancements

### Planned Features

1. **Time-based preferences** - Quiet hours, timezone support
2. **Priority levels** - Urgent vs normal notifications  
3. **Team settings** - Organization-level notification policies
4. **Rich notifications** - Images, action buttons
5. **Mobile push** - Real-time mobile notifications

### Extensibility Points

- Add new notification types in `NotificationSetting`
- Create new delivery methods in `ApplicationNotifier`
- Add custom notifier classes for specific use cases
- Extend user preferences with custom rules

## Summary

The Listopia notification system provides a robust, user-friendly way to keep collaborators informed while respecting their preferences. By using model callbacks for automatic notifications and controller actions for explicit user interactions, the system maintains consistency and provides a great user experience.

Remember: **Models for business logic, Controllers for user actions, Always respect user preferences.**