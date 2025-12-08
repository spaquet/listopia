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

  # Notify when user is assigned to an item
  def notify_item_assigned(item, assignee)
    return unless item&.list && @current_user && assignee

    # Only notify the assigned user
    ListItemAssignmentNotifier.with(
      actor_id: @current_user.id,
      list_id: item.list.id,
      item_id: item.id,
      item_title: item.title
    ).deliver([ assignee ])

    success(message: "Assignment notification sent")
  end

  # Notify about a new comment
  def notify_item_commented(comment)
    return unless comment && @current_user

    commentable = comment.commentable
    list = case commentable
    when ListItem
      commentable.list
    when List
      commentable
    else
      return
    end

    return unless list

    # Get all relevant recipients
    recipients = comment_notification_recipients(commentable, list)
    return if recipients.empty?

    ListItemCommentNotifier.with(
      actor_id: @current_user.id,
      list_id: list.id,
      commentable_id: commentable.id,
      commentable_type: commentable.class.name,
      commentable_title: commentable.title,
      comment_preview: comment.content,
      comment_id: comment.id
    ).deliver(recipients)

    success(message: "Comment notification sent")
  end

  # Notify when item is completed
  def notify_item_completed(item)
    return unless item&.list && @current_user

    recipients = list_notification_recipients(item.list)
    return if recipients.empty?

    ListItemCompletionNotifier.with(
      actor_id: @current_user.id,
      list_id: item.list.id,
      item_id: item.id,
      item_title: item.title
    ).deliver(recipients)

    success(message: "Item completion notification sent")
  end

  # Notify when item priority changes
  def notify_priority_changed(item, previous_priority)
    return unless item&.list && @current_user && item.priority_high? || item.priority_urgent?

    recipients = list_notification_recipients(item.list)
    return if recipients.empty?

    ListItemPriorityChangedNotifier.with(
      actor_id: @current_user.id,
      list_id: item.list.id,
      item_id: item.id,
      item_title: item.title,
      previous_priority: previous_priority,
      new_priority: item.priority
    ).deliver(recipients)

    success(message: "Priority change notification sent")
  end

  # Notify when collaborator permission changes
  def notify_permission_changed(collaborator, old_permission)
    return unless collaborator && collaborator.user

    ListPermissionChangedNotifier.with(
      actor_id: @current_user.id,
      list_id: collaborator.collaboratable.id,
      old_permission: old_permission,
      new_permission: collaborator.permission
    ).deliver([ collaborator.user ])

    success(message: "Permission change notification sent")
  end

  # Notify about team invitation
  def notify_team_invited(invitation)
    return unless invitation && invitation.team

    recipient = invitation.user || User.find_by(email: invitation.email)
    return unless recipient

    TeamInvitationNotifier.with(
      actor_id: @current_user&.id,
      team_name: invitation.team.name,
      organization_id: invitation.team.organization_id
    ).deliver([ recipient ])

    success(message: "Team invitation notification sent")
  end

  # Notify when list is archived
  def notify_list_archived(list)
    return unless list && @current_user

    recipients = list_notification_recipients(list)
    return if recipients.empty?

    ListArchivedNotifier.with(
      actor_id: @current_user.id,
      list_id: list.id,
      list_title: list.title,
      organization_id: list.organization_id
    ).deliver(recipients)

    success(message: "List archived notification sent")
  end

  # Notify users mentioned in a comment
  def notify_mentions(comment)
    return unless comment && @current_user

    mentioned_users = extract_mentions(comment.content)
    return if mentioned_users.empty?

    commentable = comment.commentable
    list = case commentable
    when ListItem
      commentable.list
    when List
      commentable
    else
      return
    end

    return unless list

    MentionNotifier.with(
      actor_id: @current_user.id,
      list_id: list.id,
      commentable_id: commentable.id,
      commentable_type: commentable.class.name,
      commentable_title: commentable.title,
      comment_id: comment.id
    ).deliver(mentioned_users)

    success(message: "Mention notifications sent")
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

  def comment_notification_recipients(commentable, list)
    recipients = []

    case commentable
    when ListItem
      # Notify the item assignee if applicable
      recipients << commentable.assigned_user if commentable.assigned_user && commentable.assigned_user != @current_user

      # Notify item collaborators
      item_collaborators = commentable.collaborator_users.where.not(id: @current_user.id)
      recipients.concat(item_collaborators)
    when List
      # Notify list owner
      recipients << list.owner if list.owner != @current_user

      # Notify list collaborators
      collaborators = list.collaborators.where.not(id: @current_user.id)
      recipients.concat(collaborators.map(&:user))
    end

    recipients.uniq.compact
  end

  def extract_mentions(text)
    return [] unless text.present?

    # Extract @username mentions from the text
    mention_pattern = /@(\w+)/
    mentioned_handles = text.scan(mention_pattern).flatten.uniq

    # Find users by email or name
    mentioned_users = mentioned_handles.flat_map do |handle|
      User.where("email ILIKE ? OR CONCAT(first_name, ' ', last_name) ILIKE ?", "%#{handle}%", "%#{handle}%")
           .where.not(id: @current_user.id)
    end.uniq

    mentioned_users
  end

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
