# app/mailers/notification_mailer.rb
class NotificationMailer < ApplicationMailer
  default from: "noreply@listopia.com"

  # Noticed integration - routes to appropriate method based on notification_type
  def deliver_notification(notification)
    @notification = notification
    @user = notification.recipient
    @event = notification.event

    # Route to appropriate method based on notification type
    method_name = @event.notification_type&.underscore
    return unless respond_to?(method_name, true)

    send(method_name, notification)
  end

  # Generic notification delivery
  def notification_email(notification)
    @notification = notification
    @user = notification.recipient
    @event = notification.event

    mail(
      to: @user.email,
      subject: @event.title
    )
  end

  # Item assignment notification
  def item_assigned(notification)
    @notification = notification
    @user = notification.recipient
    @event = notification.event
    @item_title = @event.params[:item_title]
    @list_title = @event.target_list&.title
    @actor_name = @event.actor_name
    @list_url = list_url(@event.target_list) if @event.target_list

    mail(
      to: @user.email,
      subject: "#{@actor_name} assigned you a task"
    )
  end

  # Comment notification
  def item_commented(notification)
    @notification = notification
    @user = notification.recipient
    @event = notification.event
    @actor_name = @event.actor_name
    @commentable_title = @event.params[:commentable_title]
    @comment_preview = @event.params[:comment_preview]&.truncate(200)
    @notification_url = notification_url(@notification)

    mail(
      to: @user.email,
      subject: "#{@actor_name} commented on #{@commentable_title}"
    )
  end

  # Item completion notification
  def item_completed(notification)
    @notification = notification
    @user = notification.recipient
    @event = notification.event
    @actor_name = @event.actor_name
    @item_title = @event.params[:item_title]
    @list_title = @event.target_list&.title
    @list_url = list_url(@event.target_list) if @event.target_list

    mail(
      to: @user.email,
      subject: "#{@actor_name} completed \"#{@item_title}\""
    )
  end

  # Priority change notification
  def priority_changed(notification)
    @notification = notification
    @user = notification.recipient
    @event = notification.event
    @actor_name = @event.actor_name
    @item_title = @event.params[:item_title]
    @new_priority = @event.params[:new_priority]&.humanize
    @list_url = list_url(@event.target_list) if @event.target_list

    mail(
      to: @user.email,
      subject: "Priority changed for \"#{@item_title}\""
    )
  end

  # Permission change notification
  def permission_changed(notification)
    @notification = notification
    @user = notification.recipient
    @event = notification.event
    @actor_name = @event.actor_name
    @new_permission = @event.params[:new_permission]
    @list_title = @event.target_list&.title
    @list_url = list_url(@event.target_list) if @event.target_list

    mail(
      to: @user.email,
      subject: "Your access to \"#{@list_title}\" has changed"
    )
  end

  # Team invitation notification
  def team_invited(notification)
    @notification = notification
    @user = notification.recipient
    @event = notification.event
    @actor_name = @event.actor_name
    @team_name = @event.params[:team_name]

    mail(
      to: @user.email,
      subject: "#{@actor_name} invited you to #{@team_name}"
    )
  end

  # List archived notification
  def list_archived(notification)
    @notification = notification
    @user = notification.recipient
    @event = notification.event
    @actor_name = @event.actor_name
    @list_title = @event.params[:list_title]

    mail(
      to: @user.email,
      subject: "\"#{@list_title}\" has been archived"
    )
  end

  # Mention notification
  def mentioned(notification)
    @notification = notification
    @user = notification.recipient
    @event = notification.event
    @actor_name = @event.actor_name
    @commentable_title = @event.params[:commentable_title]
    @comment_preview = @event.params[:comment_preview]&.truncate(200)

    mail(
      to: @user.email,
      subject: "#{@actor_name} mentioned you"
    )
  end

  # Digest notification
  def digest(notification)
    @notification = notification
    @user = notification.recipient
    @event = notification.event
    @frequency = @event.params[:frequency] || "daily"
    @item_count = @event.params[:item_count] || 0
    @comment_count = @event.params[:comment_count] || 0
    @status_count = @event.params[:status_count] || 0
    @summary_items = @event.params[:summary_items] || []

    subject_text = case @frequency
    when "weekly"
                     "Weekly digest: Your activity summary"
    else
                     "Daily digest: Your activity summary"
    end

    mail(
      to: @user.email,
      subject: subject_text
    )
  end
end
