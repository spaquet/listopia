# app/notifiers/list_item_priority_changed_notifier.rb
class ListItemPriorityChangedNotifier < ApplicationNotifier
  def notification_type
    "item_priority_changed"
  end

  def title
    "Item priority changed"
  end

  def message
    "#{actor_name} changed priority to #{humanize_priority(params[:new_priority])} for \"#{params[:item_title]}\""
  end

  def icon
    priority_icon(params[:new_priority])
  end

  def url
    list_item_path(params[:list_id], params[:item_id])
  end

  private

  def humanize_priority(priority)
    priority&.humanize || "medium"
  end

  def priority_icon(priority)
    case priority&.to_s&.downcase
    when "urgent"
      "alert-circle"
    when "high"
      "arrow-up"
    when "medium"
      "minus-circle"
    else
      "arrow-down"
    end
  end
end
