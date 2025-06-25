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
  end
end
