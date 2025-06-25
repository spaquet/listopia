# app/notifiers/list_collaboration_notifier.rb
class ListCollaborationNotifier < ApplicationNotifier
  required_params :actor_id, :list_id

  notification_methods do
    def message
      "#{actor_name} joined the list \"#{target_list&.title}\""
    end

    def title
      "New Collaborator"
    end

    def icon
      "user-plus"
    end

    def notification_type
      "collaboration"
    end
  end
end
