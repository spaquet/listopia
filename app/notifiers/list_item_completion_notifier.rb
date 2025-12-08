# app/notifiers/list_item_completion_notifier.rb
class ListItemCompletionNotifier < ApplicationNotifier
  def notification_type
    "item_completion"
  end

  def title
    "Item completed"
  end

  def message
    "#{actor_name} completed \"#{params[:item_title]}\" on #{list_name}"
  end

  def icon
    "check-circle"
  end

  def url
    list_item_path(params[:list_id], params[:item_id])
  end

  private

  def list_name
    target_list&.title || "a list"
  end
end
