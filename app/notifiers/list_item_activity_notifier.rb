# app/notifiers/list_item_activity_notifier.rb
class ListItemActivityNotifier < ApplicationNotifier
  required_params :actor_id, :list_id, :item_id, :action

  notification_methods do
    def message
      case params[:action]
      when "created"
        "#{actor_name} added \"#{item_title}\" to \"#{target_list&.title}\""
      when "updated"
        "#{actor_name} updated \"#{item_title}\" in \"#{target_list&.title}\""
      when "deleted"
        "#{actor_name} removed \"#{item_title}\" from \"#{target_list&.title}\""
      when "completed"
        "#{actor_name} completed \"#{item_title}\" in \"#{target_list&.title}\""
      when "uncompleted"
        "#{actor_name} reopened \"#{item_title}\" in \"#{target_list&.title}\""
      else
        "#{actor_name} modified an item in \"#{target_list&.title}\""
      end
    end

    def title
      case params[:action]
      when "created"
        "Item Added"
      when "updated"
        "Item Updated"
      when "deleted"
        "Item Removed"
      when "completed"
        "Item Completed"
      when "uncompleted"
        "Item Reopened"
      else
        "Item Modified"
      end
    end

    def icon
      case params[:action]
      when "created"
        "plus-circle"
      when "updated"
        "edit"
      when "deleted"
        "trash"
      when "completed"
        "check-circle"
      when "uncompleted"
        "refresh-cw"
      else
        "activity"
      end
    end

    def notification_type
      "item_activity"
    end

    def action_type
      params[:action]
    end

    private

    def item_title
      params[:item_title] || "an item"
    end
  end
end
