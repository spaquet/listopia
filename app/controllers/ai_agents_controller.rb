class AiAgentsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_organization!, only: [ :index, :create, :new ]
  before_action :set_agent, only: [ :show, :edit, :update, :destroy, :invoke, :runs ]

  def index
    @agents = policy_scope(AiAgent).includes(:ai_agent_resources, :teams).order(:scope, :name)
    @pagy, @agents = pagy(@agents)
  end

  def browse
    @agents = policy_scope(AiAgent).available.includes(:tags).group_by(&:scope)
  end

  def my_agents
    @agents = policy_scope(AiAgent).user_agent.for_user(current_user)
    @pagy, @agents = pagy(@agents)
  end

  def show
    authorize @agent
    @recent_runs = @agent.ai_agent_runs.by_user(current_user).recent.limit(5)
  end

  def new
    @agent = AiAgent.new(scope: :user_agent)
    authorize @agent
  end

  def create
    @agent = AiAgent.new(agent_params)
    @agent.user = current_user if params[:ai_agent][:scope] == "user_agent"
    @agent.organization = Current.organization unless @agent.scope_system_agent?
    authorize @agent

    if @agent.save
      redirect_to @agent, notice: "Agent created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @agent
  end

  def update
    authorize @agent
    if @agent.update(agent_params)
      redirect_to @agent, notice: "Agent updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @agent
    @agent.discard
    redirect_to ai_agents_path, notice: "Agent archived."
  end

  def invoke
    authorize @agent, :invoke?

    invocable = resolve_invocable
    run = AiAgentRun.create!(
      ai_agent: @agent,
      user: current_user,
      organization: Current.organization,
      invocable: invocable,
      user_input: params[:user_input].to_s.strip,
      input_parameters: params[:agent_parameters]&.to_unsafe_h || {}
    )

    AgentRunJob.perform_later(run.id)

    respond_to do |format|
      format.turbo_stream { render action: "invoke" }
      format.html { redirect_to ai_agent_run_path(run) }
    end
  end

  def runs
    authorize @agent, :runs?
    @runs = @agent.ai_agent_runs.by_user(current_user).recent
    @pagy, @runs = pagy(@runs)
  end

  private

  def set_agent
    @agent = AiAgent.kept.find(params[:id])
  end

  def agent_params
    permitted = params.require(:ai_agent).permit(
      :name, :description, :prompt, :scope, :model,
      :max_tokens_per_run, :max_tokens_per_day, :max_tokens_per_month,
      :timeout_seconds, :max_steps, :rate_limit_per_hour,
      :status, :tag_list, :parameters, :instructions,
      :body_context_config, :trigger_config,
      :pre_run_questions,
      metadata: {}
    )

    # Parse JSON string for parameters field
    if permitted[:parameters].is_a?(String) && permitted[:parameters].present?
      begin
        permitted[:parameters] = JSON.parse(permitted[:parameters])
      rescue JSON::ParserError
        permitted[:parameters] = {}
      end
    end

    # Parse body_context_config if string
    if permitted[:body_context_config].is_a?(String) && permitted[:body_context_config].present?
      begin
        permitted[:body_context_config] = JSON.parse(permitted[:body_context_config])
      rescue JSON::ParserError
        permitted[:body_context_config] = {}
      end
    end

    # Parse trigger_config if string
    if permitted[:trigger_config].is_a?(String) && permitted[:trigger_config].present?
      begin
        permitted[:trigger_config] = JSON.parse(permitted[:trigger_config])
      rescue JSON::ParserError
        permitted[:trigger_config] = { type: "manual" }
      end
    end

    # Parse pre_run_questions if string
    if permitted[:pre_run_questions].is_a?(String) && permitted[:pre_run_questions].present?
      begin
        permitted[:pre_run_questions] = JSON.parse(permitted[:pre_run_questions])
      rescue JSON::ParserError
        permitted[:pre_run_questions] = []
      end
    end

    permitted
  end

  def resolve_invocable
    return List.find(params[:list_id]) if params[:list_id].present?
    return ListItem.find(params[:list_item_id]) if params[:list_item_id].present?
    nil
  end
end
