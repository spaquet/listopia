# app/notifiers/list_item_assignment_notifier.rb
class ListItemAssignmentNotifier < ApplicationNotifier
  def notification_type
    "item_assignment"
  end

  def title
    "Item assigned to you"
  end

  def message
    "#{actor_name} assigned you \"#{params[:item_title]}\" on #{list_name}"
  end

  def icon
    "clipboard-list"
  end

  def url
    list_item_path(params[:list_id], params[:item_id])
  end

  private

  def list_name
    target_list&.title || "a list"
  end
end
