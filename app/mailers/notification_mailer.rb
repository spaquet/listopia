# app/mailers/notification_mailer.rb
class NotificationMailer < ApplicationMailer
  default from: "noreply@listopia.com"

  # Noticed integration - routes to appropriate method based on notification_type
  # The noticed gem's deliver method sets these parameters based on the Noticed::Notification record
  def deliver_notification
    # Guard against nil notification or missing event
    return if @notification.nil?
    return unless @notification.event.present?

    @user = @notification.recipient
    @event = @notification.event

    # Guard against missing user
    return if @user.nil?

    # Route to appropriate method based on notification type
    method_name = @event.notification_type&.underscore
    return notification_email unless method_name && respond_to?(method_name, true)

    public_send(method_name)
  end

  # Generic notification delivery
  def notification_email(notification = nil)
    # Extract user and event from notification if provided (for direct test calls)
    @user ||= notification&.recipient
    @event ||= notification&.event

    return if @user.nil? || @event.nil?

    mail(
      to: @user.email,
      subject: @event.title
    )
  end

  # Collaboration notification
  def collaboration(notification = nil)
    # Extract user and event from notification if provided (for direct test calls)
    @user ||= notification&.recipient
    @event ||= notification&.event

    return if @user.nil? || @event.nil?
    @actor_name = @event.actor_name
    @list_title = @event.target_list&.title

    mail(
      to: @user.email,
      subject: "#{@actor_name} invited you to collaborate"
    )
  end

  # Item activity notification
  def item_activity(notification = nil)
    # Extract user and event from notification if provided (for direct test calls)
    @user ||= notification&.recipient
    @event ||= notification&.event

    return if @user.nil? || @event.nil?
    @actor_name = @event.actor_name

    mail(
      to: @user.email,
      subject: "Activity on an item you follow"
    )
  end

  # Item priority changed notification
  def item_priority_changed(notification = nil)
    # Extract user and event from notification if provided (for direct test calls)
    @user ||= notification&.recipient
    @event ||= notification&.event

    return if @user.nil? || @event.nil?
    @actor_name = @event.actor_name
    @item_title = @event.params[:item_title]
    @new_priority = @event.params[:new_priority]&.humanize

    mail(
      to: @user.email,
      subject: "Priority changed for \"#{@item_title}\""
    )
  end

  # Status change notification
  def status_change(notification = nil)
    # Extract user and event from notification if provided (for direct test calls)
    @user ||= notification&.recipient
    @event ||= notification&.event

    return if @user.nil? || @event.nil?
    @actor_name = @event.actor_name

    mail(
      to: @user.email,
      subject: "Status changed on a list you follow"
    )
  end

  # List activity notification
  def list_activity(notification = nil)
    # Extract user and event from notification if provided (for direct test calls)
    @user ||= notification&.recipient
    @event ||= notification&.event

    return if @user.nil? || @event.nil?
    @actor_name = @event.actor_name
    @list_title = @event.target_list&.title

    mail(
      to: @user.email,
      subject: "Activity on \"#{@list_title}\""
    )
  end

  # Item assignment notification
  def item_assignment(notification = nil)
    # Extract user and event from notification if provided (for direct test calls)
    @user ||= notification&.recipient
    @event ||= notification&.event

    return if @user.nil? || @event.nil?
    @item_title = @event.params[:item_title]
    @list_title = @event.target_list&.title
    @actor_name = @event.actor_name
    @list_url = list_url(@event.target_list) if @event.target_list

    mail(
      to: @user.email,
      subject: "#{@actor_name} assigned you a task"
    )
  end

  # Alias for backwards compatibility with tests
  alias_method :item_assigned, :item_assignment

  # Comment notification
  def item_comment(notification = nil)
    # Extract user and event from notification if provided (for direct test calls)
    @user ||= notification&.recipient
    @event ||= notification&.event

    return if @user.nil? || @event.nil?
    @actor_name = @event.actor_name
    @commentable_title = @event.params[:commentable_title]
    @comment_preview = @event.params[:comment_preview]&.truncate(200)
    @notification_url = notification_url(@notification)

    mail(
      to: @user.email,
      subject: "#{@actor_name} commented on #{@commentable_title}"
    )
  end

  # Alias for backwards compatibility with tests
  alias_method :item_commented, :item_comment

  # Item completion notification
  def item_completion(notification = nil)
    # Extract user and event from notification if provided (for direct test calls)
    @user ||= notification&.recipient
    @event ||= notification&.event

    return if @user.nil? || @event.nil?
    @actor_name = @event.actor_name
    @item_title = @event.params[:item_title]
    @list_title = @event.target_list&.title
    @list_url = list_url(@event.target_list) if @event.target_list

    mail(
      to: @user.email,
      subject: "#{@actor_name} completed \"#{@item_title}\""
    )
  end

  # Alias for backwards compatibility with tests
  alias_method :item_completed, :item_completion

  # Priority change notification
  def priority_changed(notification = nil)(notification = nil)
    return if @user.nil? || @event.nil?
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
  def permission_changed(notification = nil)(notification = nil)
    return if @user.nil? || @event.nil?
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
  def team_invitation(notification = nil)
    # Extract user and event from notification if provided (for direct test calls)
    @user ||= notification&.recipient
    @event ||= notification&.event

    return if @user.nil? || @event.nil?
    @actor_name = @event.actor_name
    @team_name = @event.params[:team_name]

    mail(
      to: @user.email,
      subject: "#{@actor_name} invited you to #{@team_name}"
    )
  end

  # Alias for backwards compatibility with tests
  alias_method :team_invited, :team_invitation

  # List archived notification
  def list_archived(notification = nil)(notification = nil)
    return if @user.nil? || @event.nil?
    @actor_name = @event.actor_name
    @list_title = @event.params[:list_title]

    mail(
      to: @user.email,
      subject: "\"#{@list_title}\" has been archived"
    )
  end

  # Mention notification
  def mention(notification = nil)
    # Extract user and event from notification if provided (for direct test calls)
    @user ||= notification&.recipient
    @event ||= notification&.event

    return if @user.nil? || @event.nil?
    @actor_name = @event.actor_name
    @commentable_title = @event.params[:commentable_title]
    @comment_preview = @event.params[:comment_preview]&.truncate(200)

    mail(
      to: @user.email,
      subject: "#{@actor_name} mentioned you"
    )
  end

  # Alias for backwards compatibility with tests
  alias_method :mentioned, :mention

  # Digest notification
  def digest(notification = nil)
    # Extract user and event from notification if provided (for direct test calls)
    @user ||= notification&.recipient
    @event ||= notification&.event

    return if @user.nil? || @event.nil?
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
