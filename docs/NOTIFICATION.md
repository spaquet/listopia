# Notifications System

Listopia uses the **[Noticed gem](https://github.com/excid3/noticed)** to manage notifications with user preference controls. The system automatically notifies collaborators about list and item activity while respecting individual user preferences.

## Architecture

### Core Components

- **[Noticed Gem](https://rubygems.org/gems/noticed)** - Notification delivery engine
- **[NotificationSetting](../app/models/notification_setting.rb)** - User preferences (channels, types, frequency)
- **ApplicationNotifier** - Base notifier class for all custom notifiers
- **Model Callbacks** - Automatic notification triggers on data changes
- **[NotificationsController](../app/controllers/notifications_controller.rb)** - View/manage notifications

### Database Tables

- **noticed_notifications** - Stored notifications for each user
- **noticed_events** - Event records that trigger notifications
- **notification_settings** - User preference configuration

See [NotificationSetting model](../app/models/notification_setting.rb) for schema details.

## Notification Types

Listopia triggers notifications for:

### Collaboration Events
- User receives collaboration invitation
- Collaboration invitation accepted
- User removed from list collaboration

### List Activity
- List title/description changes
- List status changes (draft → active → completed → archived)

### Item Activity
- New item added to list
- Item content/priority/due date updated
- Item marked complete or uncompleted
- Item deleted from list

## User Preferences

Each user has a [NotificationSetting](../app/models/notification_setting.rb) with controls for:

### Delivery Channels
- `email_notifications` (default: true)
- `sms_notifications` (default: false)
- `push_notifications` (default: true)

### Notification Types
- `collaboration_notifications` - Invitations, collaborators added/removed
- `list_activity_notifications` - Title, description, status changes
- `item_activity_notifications` - Item creation, updates, deletion
- `status_change_notifications` - Completion/uncompleted status

### Frequency Control
- `notification_frequency` - 'immediate', 'daily_digest', 'weekly_digest', 'disabled'
- `quiet_hours_start` / `quiet_hours_end` - Time-based suppression
- `timezone` - User's timezone for delivery scheduling

## How Notifications Work

### Trigger Pattern (Model Callbacks)

```ruby
# app/models/list.rb
class List < ApplicationRecord
  after_commit :notify_title_change, on: :update, if: :saved_change_to_title?

  private

  def notify_title_change
    return unless Current.user  # Only notify if user context exists
    
    # Get recipients (exclude the person who made the change)
    recipients = collaborators.where.not(id: Current.user.id)
    return if recipients.empty?

    # Send notification with context
    ListTitleChangedNotifier.with(
      actor_id: Current.user.id,
      list_id: id,
      previous_title: title_before_last_save,
      new_title: title
    ).deliver_to_enabled_users(recipients)
  end
end
```

### Custom Notifier Example

```ruby
# app/notifiers/list_title_changed_notifier.rb
class ListTitleChangedNotifier < ApplicationNotifier
  deliver_by :database
  deliver_by :email, mailer: "NotificationMailer"

  def message
    "#{actor.name} renamed list from '#{params[:previous_title]}' to '#{params[:new_title]}'"
  end

  def notification_type
    "list_activity"
  end

  private

  def actor
    User.find(params[:actor_id])
  end
end
```

### View Notifications

Users can view notifications via [NotificationsController](../app/controllers/notifications_controller.rb):

```ruby
GET /notifications             # List all notifications
GET /notifications/:id         # View specific notification
PATCH /notifications/:id/mark_as_read
PATCH /notifications/mark_all_as_read
```

## Checking Preferences

### User Preference Helpers

```ruby
# Check if user wants a notification type
user.wants_notification?("collaboration")           # => true/false
user.wants_notification?("item_activity", :email)   # => true/false

# Check specific channels
user.notification_preferences.email_notifications?  # => true/false
user.notification_preferences.push_notifications?   # => true/false

# Check delivery frequency
user.notification_preferences.notification_frequency # => "immediate"
```

### Preference Filtering in Code

```ruby
# Always use this pattern for notifications
recipients = list.collaborators.where.not(id: Current.user.id)
return if recipients.empty?

NotifyCollaborators.with(params).deliver_to_enabled_users(recipients)
# This automatically filters based on each user's preferences
```

## Common Implementation Patterns

### 1. Exclude the Actor

```ruby
# ✅ Correct - collaborators minus the person making the change
recipients = list.collaborators.where.not(id: Current.user.id)

# ❌ Wrong - would send notification to the actor
recipients = list.collaborators
```

### 2. Check Current.user Context

```ruby
def notify_change
  # ✅ Correct - prevents notifications from console/seeds/migrations
  return unless Current.user
  
  # ❌ Wrong - triggers in background jobs without user context
  # (missing the check)
end
```

### 3. Conditional Callbacks

```ruby
# ✅ Correct - only notify on relevant changes
after_commit :notify_change, on: :update, if: :saved_change_to_title?

def saved_change_to_title?
  saved_changes.key?("title")
end

# ❌ Wrong - notifies on any change (including timestamps)
after_commit :notify_change, on: :update
```

### 4. Only Notify When Recipients Exist

```ruby
def notify_collaborators
  recipients = list.collaborators.where.not(id: Current.user.id)
  
  # ✅ Correct - don't create notifications with no recipients
  return if recipients.empty?
  
  # Proceed with notification
end
```

### 5. Deletion Notifications

```ruby
# ✅ Correct - object still exists and has data
before_destroy :notify_deletion

# ❌ Wrong - object already deleted, can't access attributes
after_destroy :notify_deletion
```

## Testing Notifications

### Test Model Callbacks

```ruby
# spec/models/list_spec.rb
describe List do
  describe "#notify_title_change" do
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

    it "doesn't notify when updated_at only changes" do
      expect {
        list.touch  # Only updates timestamp
      }.not_to have_enqueued_job(Noticed::DeliveryJob)
    end
  end
end
```

### Test Notifiers

```ruby
# spec/notifiers/list_title_changed_notifier_spec.rb
describe ListTitleChangedNotifier do
  it "generates correct message" do
    notifier = described_class.with(
      actor_id: user.id,
      list_id: list.id,
      previous_title: "Old",
      new_title: "New"
    )
    
    expect(notifier.message).to include("Old")
    expect(notifier.message).to include("New")
  end

  it "has correct notification type" do
    notifier = described_class.with(params)
    expect(notifier.notification_type).to eq("list_activity")
  end
end
```

## Notification Views

### User Settings

Users configure preferences via `/settings`:

```erb
<!-- Delivery Channels -->
<%= f.check_box :email_notifications %>
<%= f.check_box :sms_notifications %>
<%= f.check_box :push_notifications %>

<!-- Notification Types -->
<%= f.check_box :collaboration_notifications %>
<%= f.check_box :list_activity_notifications %>
<%= f.check_box :item_activity_notifications %>
<%= f.check_box :status_change_notifications %>

<!-- Frequency -->
<%= f.select :notification_frequency, 
    ['immediate', 'daily_digest', 'weekly_digest', 'disabled'] %>
```

### Notification Inbox

Notifications appear at `/notifications`:

```ruby
# Controller loads and filters notifications
@notifications = current_user.notifications
  .order(created_at: :desc)
  .includes(:event)
  .limit(50)

# Each notification delegates to its event
notification.title
notification.message
notification.actor
notification.url
```

## Configuration

### Initializer

The Noticed gem is configured in [config/initializers/noticed.rb](../config/initializers/noticed.rb):

```ruby
# Convenience methods added to Noticed::Notification
Noticed::Notification.class_eval do
  delegate :title, :message, :url, :notification_type, to: :event
  
  def read?
    read_at.present?
  end
  
  def mark_as_read!
    update!(read_at: Time.current)
  end
end
```

### Delivery Methods

Notifications can be delivered via multiple channels:

```ruby
class ApplicationNotifier < Noticed::Base
  deliver_by :database  # Store in database
  deliver_by :email     # Send email notification
  # deliver_by :sms      # Send SMS (future)
end
```

## Troubleshooting

**Notifications not sending?**
- Check `Current.user` is set in ApplicationController
- Verify recipient has `email_notifications?` true
- Check notification type matches user preferences
- View job queue: `Noticed::DeliveryJob.queue_adapter.enqueued_jobs`

**Current.user not available?**
- Set in ApplicationController: `Current.user = current_user`
- Won't work in background jobs without explicit context
- Won't work in console unless manually set

**Missing object data in destroy notifications?**
- Use `before_destroy` not `after_destroy`
- Capture data before object deletion

**Infinite notification loops?**
- Always exclude actor from recipients: `.where.not(id: Current.user.id)`
- Use conditional callbacks: `if: :saved_change_to_title?`

## Debugging

```ruby
# Check user preferences
user.notification_preferences
user.wants_notification?("collaboration")

# View recent notifications
user.notifications.order(created_at: :desc).limit(10)

# Check queued jobs
Noticed::DeliveryJob.queue_adapter.enqueued_jobs

# Generate test token in console
Current.user = User.first
list = List.first
list.update!(title: "Test") # Triggers notification
```

## Performance Notes

- Notifications are **async** via background jobs (Solid Queue)
- Only notifications with recipients are created
- Early exit conditions prevent unnecessary queries
- Seen/read tracking via `seen_at` and `read_at` timestamps

## Future Enhancements

1. **SMS delivery** - Add SMS channel for critical notifications
2. **Webhooks** - External system notifications
3. **Custom frequency** - Per-notification-type frequency settings
4. **Rich notifications** - Attachments, action buttons, deep links
5. **Bulk operations** - Notify about batch changes