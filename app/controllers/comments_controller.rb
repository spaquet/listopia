# app/controllers/comments_controller.rb
class CommentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_commentable
  before_action :set_comment, only: [ :destroy ]
  before_action :authorize_comment_access!

  def create
    @comment = @commentable.comments.build(comment_params)
    @comment.user = current_user

    if @comment.save
      respond_to do |format|
        format.html { redirect_to @commentable, notice: "Comment was successfully added." }
        format.turbo_stream do
          render turbo_stream: [
            # Replace the entire comments container to handle empty->filled transition
            turbo_stream.replace(
              "comments_container_#{@commentable.class.name.downcase}_#{@commentable.id}",
              partial: "comments/comments_container",
              locals: { commentable: @commentable }
            ),
            # Clear and reset the form
            turbo_stream.replace(
              "new_comment_form_#{@commentable.class.name.downcase}_#{@commentable.id}",
              partial: "comments/form",
              locals: { commentable: @commentable, comment: @commentable.comments.build }
            )
          ]
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to @commentable, alert: "Unable to add comment." }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "new_comment_form_#{@commentable.class.name.downcase}_#{@commentable.id}",
            partial: "comments/form",
            locals: { commentable: @commentable, comment: @comment }
          ), status: :unprocessable_entity
        end
      end
    end
  end

  def destroy
    authorize @comment
    commentable = @comment.commentable
    comment_id = @comment.id  # Capture ID before deletion
    @comment.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          # First: Remove the individual comment frame
          turbo_stream.remove("comment_#{comment_id}"),
          # Second: Update the container (updates comment count, handles empty state)
          turbo_stream.replace(
            "comments_container_#{commentable.class.name.downcase}_#{commentable.id}",
            partial: "comments/comments_container",
            locals: { commentable: commentable }
          )
        ]
      end
    end
  end

  private

  def set_commentable
    # Check list_item_id FIRST because the route includes both list_id and list_item_id
    if params[:list_item_id]
      @commentable = ListItem.find(params[:list_item_id])
    elsif params[:list_id]
      @commentable = List.find(params[:list_id])
    else
      redirect_to root_path, alert: "Invalid resource."
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Resource not found."
  end

  def set_comment
    @comment = Comment.find(params[:id])
  end

  def authorize_comment_access!
    authorize @commentable, :show?
  end

  def comment_params
    params.require(:comment).permit(:content)
  end
end
