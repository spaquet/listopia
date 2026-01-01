# app/controllers/notifications_controller.rb
class NotificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_notification_service

  def index
    @notifications = filter_notifications
    @notification_stats = @notification_service.notification_stats

    # Mark all notifications as seen when viewing the page
    @notification_service.mark_as_seen

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def show
    @notification = current_user.notifications.find(params[:id])
    @notification_service.mark_as_read(@notification.id)

    # Redirect to the notification's target URL
    if @notification.url.present?
      redirect_to @notification.url
    else
      redirect_to notifications_path, alert: "This notification doesn't have a target URL"
    end
  end

  def mark_as_read
    result = @notification_service.mark_as_read(params[:id])

    respond_to do |format|
      if result.success?
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "notification_#{params[:id]}",
            partial: "notifications/notification",
            locals: { notification: result.data }
          )
        }
        format.json { render json: { status: "success" } }
      else
        format.json { render json: { status: "error", errors: result.errors } }
      end
    end
  end

  def mark_all_as_read
    result = @notification_service.mark_all_as_read

    respond_to do |format|
      if result.success?
        format.turbo_stream {
          render turbo_stream: [
            turbo_stream.replace("notifications_list", partial: "notifications/list", locals: { notifications: current_user.notifications.includes(:event).order(created_at: :desc) }),
            turbo_stream.replace("notification_bell", partial: "shared/notification_bell")
          ]
        }
        format.json { render json: { status: "success" } }
      else
        format.json { render json: { status: "error", errors: result.errors } }
      end
    end
  end

  def mark_all_as_seen
    result = @notification_service.mark_as_seen

    respond_to do |format|
      if result.success?
        format.json { render json: { status: "success" } }
      else
        format.json { render json: { status: "error", errors: result.errors } }
      end
    end
  end

  def stats
    stats = @notification_service.notification_stats
    render json: stats
  end

  private

  def set_notification_service
    @notification_service = NotificationService.new(current_user)
  end

  def filter_notifications
    notifications = current_user.notifications.includes(:event)

    # Filter by read status
    case params[:filter_read]
    when "read"
      notifications = notifications.where.not(read_at: nil)
    when "unread"
      notifications = notifications.where(read_at: nil)
    end

    # Filter by notification type
    if params[:filter_type].present?
      notifications = notifications.joins(:event).where(
        noticed_events: { type: notifier_class_for_type(params[:filter_type]) }
      )
    end

    # Filter by list
    if params[:filter_list_id].present?
      notifications = notifications.joins(:event).where(
        "noticed_events.params ->> 'list_id' = ?", params[:filter_list_id]
      )
    end

    # Filter by date range
    if params[:filter_date].present?
      case params[:filter_date]
      when "today"
        notifications = notifications.where(created_at: Date.current.all_day)
      when "week"
        notifications = notifications.where(created_at: 1.week.ago..Time.current)
      when "month"
        notifications = notifications.where(created_at: 1.month.ago..Time.current)
      end
    end

    # Sort notifications
    case params[:sort]
    when "oldest"
      notifications = notifications.order(created_at: :asc)
    else
      notifications = notifications.order(created_at: :desc)
    end

    # Paginate
    notifications.limit(50).offset(params[:offset].to_i)
  end

  def notifier_class_for_type(type)
    case type
    when "collaboration"
      "ListCollaborationNotifier"
    when "list_status"
      "ListStatusChangedNotifier"
    when "item_activity"
      "ListItemActivityNotifier"
    end
  end
end
