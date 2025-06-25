# app/notifiers/list_status_changed_notifier.rb
class ListStatusChangedNotifier < ApplicationNotifier
  required_params :actor_id, :list_id, :previous_status, :new_status

  notification_methods do
    def message
      "#{actor_name} changed \"#{target_list&.title}\" status from #{params[:previous_status].humanize} to #{params[:new_status].humanize}"
    end

    def title
      "List Status Changed"
    end

    def icon
      case params[:new_status]
      when "completed"
        "check-circle"
      when "archived"
        "archive"
      when "active"
        "play-circle"
      else
        "edit"
      end
    end

    def notification_type
      "list_status"
    end

    def previous_status
      params[:previous_status]
    end

    def new_status
      params[:new_status]
    end
  end
end
