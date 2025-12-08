# app/controllers/message_feedbacks_controller.rb
#
# Handles message rating/feedback submission
# Allows users to rate assistant responses

class MessageFeedbacksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_message
  before_action :authorize_feedback

  def create
    # Check if user already rated this message
    existing_feedback = @message.feedbacks.find_by(user: current_user)

    if existing_feedback
      existing_feedback.update(feedback_params)
      @feedback = existing_feedback
    else
      @feedback = @message.feedbacks.build(feedback_params)
      @feedback.user = current_user
      @feedback.chat = @message.chat
    end

    if @feedback.save
      respond_to do |format|
        format.json { render json: { success: true, feedback: @feedback } }
        format.turbo_stream
      end
    else
      respond_to do |format|
        format.json { render json: { success: false, errors: @feedback.errors }, status: :unprocessable_entity }
        format.turbo_stream { render action: :error, status: :unprocessable_entity }
      end
    end
  end

  private

  def set_message
    @message = Message.find(params[:message_id])
  end

  def authorize_feedback
    chat = @message.chat
    authorize chat
    # User cannot rate their own messages
    if @message.user_id == current_user.id
      head :forbidden
    end
  end

  def feedback_params
    params.require(:message_feedback).permit(:rating, :feedback_type, :comment, :helpfulness_score)
  end
end
