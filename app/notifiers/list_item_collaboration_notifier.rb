# app/notifiers/list_item_collaboration_notifier.rb
class ListItemCollaborationNotifier < ApplicationNotifier
  required_params :actor_id, :list_item_id, :list_id

  notification_methods do
    def message
      "#{actor_name} invited you to collaborate on \"#{target_item&.title}\""
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
