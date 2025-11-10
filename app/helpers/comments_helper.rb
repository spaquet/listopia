# app/helpers/comments_helper.rb
module CommentsHelper
  # Helper method to generate the correct delete path for a comment
  # since comments are nested under commentables (List, ListItem)
  def comment_delete_path(comment)
    case comment.commentable_type
    when "List"
      list_comment_path(comment.commentable, comment)
    when "ListItem"
      list_list_item_comment_path(comment.commentable.list, comment.commentable, comment)
    else
      raise "Unknown commentable type: #{comment.commentable_type}"
    end
  end
end
