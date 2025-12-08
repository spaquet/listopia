# app/notifiers/list_permission_changed_notifier.rb
class ListPermissionChangedNotifier < ApplicationNotifier
  def notification_type
    "permission_changed"
  end

  def title
    "Your access has changed"
  end

  def message
    "#{actor_name} changed your permission to #{humanize_permission(params[:new_permission])} on #{list_name}"
  end

  def icon
    "lock"
  end

  def url
    list_path(params[:list_id])
  end

  private

  def humanize_permission(permission)
    case permission&.to_s&.downcase
    when "view"
      "Viewer"
    when "comment"
      "Commenter"
    when "edit"
      "Editor"
    when "admin"
      "Admin"
    else
      permission&.humanize || "Viewer"
    end
  end

  def list_name
    target_list&.title || "a list"
  end
end
