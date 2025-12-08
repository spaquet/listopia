# app/notifiers/mention_notifier.rb
class MentionNotifier < ApplicationNotifier
  def notification_type
    "mention"
  end

  def title
    "You were mentioned"
  end

  def message
    "#{actor_name} mentioned you in a comment on #{commentable_name}"
  end

  def icon
    "at-sign"
  end

  def url
    case params[:commentable_type]
    when "List"
      list_path(params[:commentable_id])
    when "ListItem"
      list_item_path(params[:list_id], params[:commentable_id])
    else
      list_path(params[:list_id])
    end
  end

  private

  def commentable_name
    case params[:commentable_type]
    when "List"
      "\"#{params[:commentable_title]}\""
    when "ListItem"
      "\"#{params[:commentable_title]}\""
    else
      "a resource"
    end
  end
end
