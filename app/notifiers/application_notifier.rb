# app/notifiers/application_notifier.rb
class ApplicationNotifier < Noticed::Event
  # Base class for all notifiers with common functionality

  deliver_by :database do |config|
    config.association = :notifications
  end

  notification_methods do
    # Helper to get the actor (user who triggered the notification)
    def actor
      User.find(params[:actor_id]) if params[:actor_id]
    end

    # Helper to get the target list
    def target_list
      List.find(params[:list_id]) if params[:list_id]
    end

    # Helper to format actor name
    def actor_name
      actor&.name || "Someone"
    end

    # Helper to get notification icon
    def icon
      "bell"
    end

    # Default URL - can be overridden
    def url
      target_list ? list_path(target_list) : dashboard_path
    end

    # Delivery filter to only deliver to users who have enabled this notification type
    def self.deliver_to_enabled_users(recipients)
    # Filter recipients who want this notification type
    notification_type = new.notification_type
    enabled_recipients = recipients.select do |user|
      user.wants_notification?(notification_type)
    end

    deliver_later(enabled_recipients) if enabled_recipients.any?
  end
  end
end
