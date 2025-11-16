class TeamMembersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization
  before_action :set_team
  before_action :set_member, only: [:show, :edit, :update, :update_role, :remove]
  before_action :authorize_access!

  def index
    authorize @team, :manage_members?
    @pagy, @members = pagy(@team.team_memberships.includes(:user).order(created_at: :desc))
  end

  def show
    authorize @team, :manage_members?
  end

  def new
    authorize @team, :manage_members?
    # Only show org members who aren't already on the team
    @available_members = @organization.users.where.not(id: @team.users.select(:id))
  end

  def create
    authorize @team, :manage_members?

    user_id = params[:user_id]
    user = User.find(user_id)

    # Verify user is in organization
    org_membership = @organization.organization_memberships.find_by(user: user)
    unless org_membership
      redirect_to organization_team_members_path(@organization, @team), alert: "User is not a member of this organization."
      return
    end

    # Create team membership
    membership = @team.team_memberships.build(
      user: user,
      organization_membership: org_membership,
      role: params[:role] || 'member'
    )

    if membership.save
      respond_to do |format|
        format.html { redirect_to organization_team_members_path(@organization, @team), notice: "Member added to team." }
        format.turbo_stream
      end
    else
      respond_to do |format|
        format.html { redirect_to organization_team_members_path(@organization, @team), alert: "Unable to add member." }
      end
    end
  end

  def update_role
    authorize @team, :update_member_role?

    if @member.update(role: params[:role])
      respond_to do |format|
        format.html { redirect_to organization_team_members_path(@organization, @team), notice: "Member role updated." }
        format.turbo_stream { render action: :update_role }
      end
    else
      respond_to do |format|
        format.html { redirect_to organization_team_members_path(@organization, @team), alert: "Unable to update role." }
      end
    end
  end

  def remove
    authorize @team, :manage_members?

    if @member.destroy
      respond_to do |format|
        format.html { redirect_to organization_team_members_path(@organization, @team), notice: "Member removed from team." }
        format.turbo_stream { render action: :remove }
      end
    else
      respond_to do |format|
        format.html { redirect_to organization_team_members_path(@organization, @team), alert: "Unable to remove member." }
      end
    end
  end

  private

  def set_organization
    @organization = Organization.find(params[:organization_id])
  end

  def set_team
    @team = @organization.teams.find(params[:team_id])
  end

  def set_member
    @member = @team.team_memberships.find(params[:id])
  end

  def authorize_access!
    authorize @team, :manage_members?
  end
end
