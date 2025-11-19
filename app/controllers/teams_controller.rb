class TeamsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization
  before_action :set_team, only: [:show, :edit, :update, :destroy]
  before_action :authorize_org!

  def index
    authorize @organization, :manage_teams?
    @pagy, @teams = pagy(@organization.teams.order(created_at: :desc))
  end

  def show
    authorize @team, :show?
  end

  def new
    authorize @organization, :manage_teams?
    @team = @organization.teams.build
  end

  def create
    authorize @organization, :manage_teams?
    @team = @organization.teams.build(team_params)
    @team.creator = current_user

    if @team.save
      redirect_to organization_team_path(@organization, @team), notice: "Team created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @team, :update?
  end

  def update
    authorize @team, :update?

    if @team.update(team_params)
      redirect_to organization_team_path(@organization, @team), notice: "Team updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @team, :destroy?

    if @team.destroy
      redirect_to organization_teams_path(@organization), notice: "Team deleted successfully."
    else
      redirect_to organization_team_path(@organization, @team), alert: "Unable to delete team."
    end
  end

  private

  def set_organization
    @organization = Organization.find(params[:organization_id])
  end

  def set_team
    @team = @organization.teams.find(params[:id])
  end

  def team_params
    params.require(:team).permit(:name)
  end

  def authorize_org!
    authorize @organization, :show?
  end
end
