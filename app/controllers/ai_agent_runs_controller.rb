class AiAgentRunsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_run, only: [ :show, :pause, :resume, :cancel ]

  def index
    @runs = policy_scope(AiAgentRun).includes(:ai_agent).recent
    @pagy, @runs = pagy(@runs)
  end

  def show
    authorize @run
    @steps = @run.ai_agent_run_steps.order(step_number: :asc)
  end

  def create
    agent = AiAgent.kept.find(params[:ai_agent_id])
    authorize AiAgentRun.new(ai_agent: agent), :create?

    invocable = resolve_invocable_from_params
    @run = AiAgentRun.create!(
      ai_agent: agent,
      user: current_user,
      organization: Current.organization,
      invocable: invocable,
      user_input: params[:user_input].to_s.strip,
      input_parameters: params[:agent_parameters]&.to_unsafe_h || {}
    )
    AgentRunJob.perform_later(@run.id)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to ai_agent_run_path(@run) }
    end
  end

  def pause
    authorize @run, :pause?
    @run.pause!
    respond_with_status_update
  end

  def resume
    authorize @run, :resume?
    @run.resume!
    AgentRunJob.perform_later(@run.id)
    respond_with_status_update
  end

  def cancel
    authorize @run, :cancel?
    @run.cancel!(reason: params[:reason])
    respond_with_status_update
  end

  private

  def set_run
    @run = AiAgentRun.find(params[:id])
  end

  def respond_with_status_update
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "agent-run-status-#{@run.id}",
          partial: "ai_agents/run_status",
          locals: { run: @run }
        )
      end
      format.html { redirect_to ai_agent_run_path(@run) }
    end
  end

  def resolve_invocable_from_params
    return List.find(params[:list_id]) if params[:list_id].present?
    return ListItem.find(params[:list_item_id]) if params[:list_item_id].present?
    nil
  end
end
