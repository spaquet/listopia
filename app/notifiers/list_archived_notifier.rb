# app/notifiers/list_archived_notifier.rb
class ListArchivedNotifier < ApplicationNotifier
  def notification_type
    "list_archived"
  end

  def title
    "List archived"
  end

  def message
    "#{actor_name} archived the \"#{params[:list_title]}\" list"
  end

  def icon
    "archive"
  end

  def url
    # Link to the organization or dashboard since the list is archived
    if params[:organization_id]
      organization_path(params[:organization_id])
    else
      dashboard_path
    end
  end
end
