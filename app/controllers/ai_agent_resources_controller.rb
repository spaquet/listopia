class AiAgentResourcesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_agent
  before_action :set_resource, only: [ :edit, :update, :destroy ]

  def new
    @resource = @agent.ai_agent_resources.build
    authorize @resource
    respond_to do |format|
      format.turbo_stream { render "new" }
      format.html { redirect_to ai_agent_path(@agent) }
    end
  end

  def create
    @resource = @agent.ai_agent_resources.build(resource_params)
    authorize @resource
    if @resource.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to ai_agent_path(@agent) }
      end
    else
      respond_to do |format|
        format.turbo_stream { render "new", status: :unprocessable_entity }
        format.html { redirect_to ai_agent_path(@agent) }
      end
    end
  end

  def edit
    authorize @resource
    respond_to do |format|
      format.turbo_stream { render "edit" }
      format.html { render :edit }
    end
  end

  def update
    authorize @resource
    if @resource.update(resource_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to ai_agent_path(@agent) }
      end
    else
      respond_to do |format|
        format.turbo_stream { render "edit", status: :unprocessable_entity }
        format.html { render :edit }
      end
    end
  end

  def destroy
    authorize @resource
    @resource.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to ai_agent_path(@agent) }
    end
  end

  private

  def set_agent
    @agent = AiAgent.kept.find(params[:ai_agent_id])
  end

  def set_resource
    @resource = @agent.ai_agent_resources.find(params[:id])
  end

  def resource_params
    params.require(:ai_agent_resource).permit(:resource_type, :permission, :description, :resource_identifier, :enabled)
  end
end
