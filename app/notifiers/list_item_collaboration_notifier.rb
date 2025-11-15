# app/notifiers/list_item_collaboration_notifier.rb
class ListItemCollaborationNotifier < ApplicationNotifier
  required_params :actor_id, :list_item_id, :list_id

  notification_methods do
    def message
      action = params[:action] || "invited"
      if action == "removed"
        "#{actor_name} removed you from \"#{target_item&.title}\""
      else
        "#{actor_name} invited you to collaborate on \"#{target_item&.title}\""
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
      list_list_item_path(target_list, target_item)
    end
  end

  private

  def target_item
    ListItem.find(params[:list_item_id]) if params[:list_item_id]
  end

  def target_list
    List.find(params[:list_id]) if params[:list_id]
  end
end
