class AiAgentFeedbacksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_run

  def create
    @feedback = AiAgentFeedback.find_or_initialize_by(
      ai_agent_run: @run,
      user: current_user
    )
    @feedback.ai_agent = @run.ai_agent
    @feedback.assign_attributes(feedback_params)
    authorize @feedback

    if @feedback.save
      respond_to do |format|
        format.turbo_stream { render action: "create" }
        format.json { render json: { success: true } }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :error, status: :unprocessable_entity }
        format.json { render json: { errors: @feedback.errors }, status: :unprocessable_entity }
      end
    end
  end

  private

  def set_run
    @run = AiAgentRun.find(params[:ai_agent_run_id])
  end

  def feedback_params
    params.require(:ai_agent_feedback).permit(:rating, :feedback_type, :comment, :helpfulness_score)
  end
end
