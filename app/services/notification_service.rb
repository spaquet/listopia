# app/services/notification_service.rb
class NotificationService < ApplicationService
  def initialize(current_user)
    @current_user = current_user
  end

  # Notify collaborators when someone joins a list
  def notify_collaboration_joined(list, new_collaborator)
    return unless list && new_collaborator && @current_user

    # Don't notify the person who was added
    recipients = list.collaborators.where.not(id: new_collaborator.id)
    recipients = recipients.where.not(id: @current_user.id) if @current_user != new_collaborator

    return if recipients.empty?

    ListCollaborationNotifier.with(
      actor_id: @current_user.id,
      list_id: list.id,
      new_collaborator_id: new_collaborator.id
    ).deliver(recipients)

    success(message: "Collaboration notifications sent")
  end

  # Notify collaborators when list status changes
  def notify_list_status_changed(list, previous_status, new_status)
    return unless list && @current_user && previous_status != new_status

    # Get all collaborators except the actor
    recipients = list_notification_recipients(list)
    return if recipients.empty?

    ListStatusChangedNotifier.with(
      actor_id: @current_user.id,
      list_id: list.id,
      previous_status: previous_status,
      new_status: new_status
    ).deliver(recipients)

    success(message: "Status change notifications sent")
  end

  # Notify collaborators about item activity (only for active lists)
  def notify_item_activity(list_item, action, previous_title = nil)
    return unless list_item&.list && @current_user
    return unless list_item.list.status_active? # Only notify for active lists

    # Get all collaborators except the actor
    recipients = list_notification_recipients(list_item.list)
    return if recipients.empty?

    ListItemActivityNotifier.with(
      actor_id: @current_user.id,
      list_id: list_item.list.id,
      item_id: list_item.id,
      item_title: previous_title || list_item.title,
      action: action
    ).deliver(recipients)

    success(message: "Item activity notifications sent")
  end

  # Mark notification as read
  def mark_as_read(notification_id)
    notification = @current_user.notifications.find(notification_id)
    notification.update!(read_at: Time.current)
    success(data: notification)
  rescue ActiveRecord::RecordNotFound
    failure(errors: "Notification not found")
  end

  # Mark all notifications as read
  def mark_all_as_read
    @current_user.notifications.where(read_at: nil).update_all(read_at: Time.current)
    success(message: "All notifications marked as read")
  end

  # Mark notification as seen (for bell icon count)
  def mark_as_seen(notification_ids = nil)
    notifications = if notification_ids
      @current_user.notifications.where(id: notification_ids)
    else
      @current_user.notifications.where(seen_at: nil)
    end

    notifications.update_all(seen_at: Time.current)
    success(message: "Notifications marked as seen")
  end

  # Get notification stats for current user
  def notification_stats
    {
      total: @current_user.notifications.count,
      unread: @current_user.notifications.where(read_at: nil).count,
      unseen: @current_user.notifications.where(seen_at: nil).count
    }
  end

  private

  def list_notification_recipients(list)
    # Get all users who should receive notifications for this list
    recipients = []

    # Add list owner (unless they're the actor)
    recipients << list.owner unless list.owner.id == @current_user.id

    # Add collaborators (except the actor)
    collaborators = list.collaborators.where.not(id: @current_user.id)
    recipients.concat(collaborators)

    recipients.uniq.compact
  end
end
