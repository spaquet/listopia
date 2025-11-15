# app/notifiers/list_collaboration_notifier.rb
class ListCollaborationNotifier < ApplicationNotifier
  required_params :actor_id, :list_id

  notification_methods do
    def message
      action = params[:action] || "invited"
      if action == "removed"
        "#{actor_name} removed you from \"#{target_list&.title}\""
      else
        "#{actor_name} invited you to collaborate on \"#{target_list&.title}\""
      end
    end

    def title
      action = params[:action] || "invited"
      action == "removed" ? "Removed from collaboration" : "Collaboration invitation"
    end

    def icon
      action = params[:action] || "invited"
      action == "removed" ? "user-minus" : "share-2"
    end

    def notification_type
      "collaboration"
    end

    def url
      list_path(target_list)
    end
  end
end
