# app/notifiers/list_collaboration_notifier.rb
class ListCollaborationNotifier < ApplicationNotifier
  required_params :actor_id, :list_id

  notification_methods do
    def message
      "#{actor_name} invited you to collaborate on \"#{target_list&.title}\""
    end

    def title
      "Collaboration invitation"
    end

    def icon
      "share-2"
    end

    def notification_type
      "collaboration"
    end

    def url
      list_path(target_list)
    end
  end
end
