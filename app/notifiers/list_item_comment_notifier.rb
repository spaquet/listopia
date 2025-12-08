# app/notifiers/list_item_comment_notifier.rb
class ListItemCommentNotifier < ApplicationNotifier
  def notification_type
    "item_comment"
  end

  def title
    "New comment on \"#{params[:commentable_title]}\""
  end

  def message
    "#{actor_name} commented: \"#{truncate_comment(params[:comment_preview])}\""
  end

  def icon
    "message-square"
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

  def truncate_comment(text)
    text&.truncate(100) || ""
  end
end
