# app/controllers/team_members_controller.rb
class TeamMembersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization
  before_action :set_team
  before_action :set_member, only: [ :update_role, :remove ]
  before_action :set_invitation, only: [ :resend_invitation, :cancel_invitation ]

  def new
    authorize @team, :manage_members?
    # Only show org members who aren't already on the team
    @available_members = @organization.users.where.not(id: @team.users.select(:id))
  end

  def create
    authorize @team, :manage_members?

    if params[:invitation_type] == "bulk"
      # Handle bulk email invitations
      emails = params[:emails]
      role = params[:role] || "member"

      service = TeamInvitationService.new(@team, current_user, emails, role)
      results = service.invite_users

      message = build_invitation_message(results)
      redirect_to organization_team_path(@organization, @team), notice: message
    else
      # Handle single user selection
      user_id = params[:user_id]
      user = User.find(user_id)

      # Verify user is in organization
      org_membership = @organization.organization_memberships.find_by(user: user)
      unless org_membership
        redirect_to organization_team_path(@organization, @team), alert: "User is not a member of this organization."
        return
      end

      # Create team membership
      @member = @team.team_memberships.build(
        user: user,
        organization_membership: org_membership,
        role: params[:role] || "member"
      )

      if @member.save
        redirect_to organization_team_path(@organization, @team), notice: "Member added to team."
      else
        respond_to do |format|
          format.html { redirect_to organization_team_path(@organization, @team), alert: "Unable to add member." }
        end
      end
    end
  end

  def search
    authorize @team, :manage_members?
    query = params[:q].to_s.strip

    # Get organization members not already in team
    available_members = @organization.users.where.not(id: @team.users.select(:id))

    if query.present?
      # Search by email or name
      @search_results = available_members.where(
        "email ILIKE ? OR name ILIKE ?",
        "%#{query}%",
        "%#{query}%"
      ).limit(10)
    else
      @search_results = []
    end

    respond_to do |format|
      format.turbo_stream
    end
  end

  def update_role
    authorize @team, :update_member_role?

    # Prevent users from changing their own role
    if @member.user == current_user
      respond_to do |format|
        format.html { redirect_to organization_team_path(@organization, @team), alert: "You cannot change your own role." }
        format.turbo_stream { render plain: "error", status: :forbidden }
      end
      return
    end

    if @member.update(role: params[:role])
      respond_to do |format|
        format.html { redirect_to organization_team_path(@organization, @team), notice: "Member role updated." }
        format.turbo_stream { render action: :update_role }
      end
    else
      respond_to do |format|
        format.html { redirect_to organization_team_path(@organization, @team), alert: "Unable to update role." }
        format.turbo_stream { render plain: "error", status: :unprocessable_entity }
      end
    end
  end

  def remove
    authorize @team, :manage_members?

    # Prevent users from removing themselves
    if @member.user == current_user
      respond_to do |format|
        format.html { redirect_to organization_team_path(@organization, @team), alert: "You cannot remove yourself from the team." }
        format.turbo_stream { render plain: "error", status: :forbidden }
      end
      return
    end

    if @member.destroy
      respond_to do |format|
        format.html { redirect_to organization_team_path(@organization, @team), notice: "Member removed from team." }
        format.turbo_stream { render action: :remove }
      end
    else
      respond_to do |format|
        format.html { redirect_to organization_team_path(@organization, @team), alert: "Unable to remove member." }
        format.turbo_stream { render plain: "error", status: :unprocessable_entity }
      end
    end
  end

  def resend_invitation
    authorize @team, :manage_members?

    # Regenerate the invitation token so it's valid for another 7 days
    @invitation.update(invitation_token: @invitation.generate_token_for(:invitation), invitation_sent_at: Time.current)

    # Resend the invitation email
    CollaborationMailer.team_member_invitation(@invitation).deliver_later

    respond_to do |format|
      format.html { redirect_to organization_team_path(@organization, @team), notice: "Invitation resent to #{@invitation.email}." }
      format.turbo_stream { render action: :resend_invitation }
    end
  end

  def cancel_invitation
    authorize @team, :manage_members?

    if @invitation.destroy
      respond_to do |format|
        format.html { redirect_to organization_team_path(@organization, @team), notice: "Invitation cancelled." }
        format.turbo_stream { render action: :cancel_invitation }
      end
    else
      respond_to do |format|
        format.html { redirect_to organization_team_path(@organization, @team), alert: "Unable to cancel invitation." }
        format.turbo_stream { render plain: "error", status: :unprocessable_entity }
      end
    end
  end

  private

  def build_invitation_message(results)
    message_parts = []
    message_parts << "Added #{results[:created].length} member(s)" if results[:created].any?
    message_parts << "#{results[:already_member].length} already member(s)" if results[:already_member].any?
    message_parts << "#{results[:invalid].length} invalid invitation(s)" if results[:invalid].any?

    message_parts.join(", ")
  end

  def set_organization
    @organization = Organization.find(params[:organization_id])
  end

  def set_team
    @team = @organization.teams.find(params[:team_id])
  end

  def set_member
    @member = @team.team_memberships.find(params[:id])
  end

  def set_invitation
    @invitation = Invitation.find(params[:id])
  end
end
