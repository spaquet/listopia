class AiAgentRunsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_run, only: [ :show, :pause, :resume, :cancel, :submit_pre_run_answers, :answer_interaction ]

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

  def submit_pre_run_answers
    authorize @run, :submit_pre_run_answers?
    return render json: { error: "Run not awaiting input" }, status: :unprocessable_entity unless @run.status_awaiting_input?

    @run.update!(pre_run_answers: params[:answers]&.to_unsafe_h || {})
    AgentRunJob.perform_later(@run.id)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "agent-run-container-#{@run.id}",
          partial: "ai_agents/run_status",
          locals: { run: @run }
        )
      end
      format.html { redirect_to ai_agent_run_path(@run) }
    end
  end

  def answer_interaction
    authorize @run, :answer_interaction?

    interaction = AiAgentInteraction.find_by(id: params[:interaction_id], ai_agent_run_id: @run.id)
    return render json: { error: "Interaction not found" }, status: :not_found unless interaction

    return render json: { error: "Interaction already answered" }, status: :unprocessable_entity unless interaction.pending_status?

    interaction.mark_answered!(params[:answer])

    # Resume the run
    @run.resume!
    AgentRunJob.perform_later(@run.id)

    respond_to do |format|
      format.turbo_stream do
        # If the run was triggered from a chat, broadcast the answer confirmation to chat
        if @run.invocable.is_a?(Chat)
          chat = @run.invocable
          chat_message_id = @run.input_parameters&.dig("chat_message_id")
          target = chat_message_id ? "message-#{chat_message_id}" : "chat-loading-#{chat.id}"
          channel = "chat_#{chat.id}"

          render turbo_stream: turbo_stream.replace(
            "message-hitl-#{interaction.id}",
            partial: "chats/hitl_answered",
            locals: { interaction: interaction }
          )
        else
          # For show.html.erb view, replace the interaction form
          render turbo_stream: [
            turbo_stream.replace(
              "interaction-#{interaction.id}",
              partial: "ai_agents/interaction_answered",
              locals: { interaction: interaction }
            ),
            turbo_stream.replace(
              "agent-run-status-#{@run.id}",
              partial: "ai_agents/run_status",
              locals: { run: @run }
            )
          ]
        end
      end
      format.html { redirect_to ai_agent_run_path(@run) }
    end
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
