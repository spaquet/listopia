class OrganizationMembersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization
  before_action :set_member, only: [:show, :edit, :update, :update_role, :remove]
  before_action :authorize_access!

  def index
    authorize @organization, :manage_members?
    @pagy, @members = pagy(@organization.organization_memberships.includes(:user).order(created_at: :desc))
  end

  def show
    authorize @organization, :manage_members?
  end

  def new
    authorize @organization, :invite_member?
    @invitation = @organization.invitations.build
  end

  def create
    authorize @organization, :invite_member?

    emails = params[:emails]
    role = params[:role] || 'member'

    # Use the service to handle invitations
    service = OrganizationInvitationService.new(@organization, current_user, emails, role)
    results = service.invite_users

    # Build response message
    message = build_invitation_message(results)

    respond_to do |format|
      format.html { redirect_to organization_members_path(@organization), notice: message }
      format.turbo_stream
    end
  end

  def update_role
    authorize @organization, :update_member_role?

    if @member.update(role: params[:role])
      respond_to do |format|
        format.html { redirect_to organization_members_path(@organization), notice: "Member role updated." }
        format.turbo_stream { render action: :update_role }
      end
    else
      respond_to do |format|
        format.html { redirect_to organization_members_path(@organization), alert: "Unable to update role." }
      end
    end
  end

  def remove
    authorize @organization, :remove_member?

    # Prevent removing the last owner
    if @member.role_owner? && @organization.organization_memberships.where(role: 'owner').count == 1
      redirect_to organization_members_path(@organization), alert: "Cannot remove the last owner."
      return
    end

    if @member.destroy
      respond_to do |format|
        format.html { redirect_to organization_members_path(@organization), notice: "Member removed successfully." }
        format.turbo_stream { render action: :remove }
      end
    else
      respond_to do |format|
        format.html { redirect_to organization_members_path(@organization), alert: "Unable to remove member." }
      end
    end
  end

  private

  def set_organization
    @organization = Organization.find(params[:organization_id])
  end

  def set_member
    @member = @organization.organization_memberships.find(params[:id])
  end

  def authorize_access!
    authorize @organization, :manage_members?
  end

  def build_invitation_message(results)
    messages = []
    messages << "#{results[:created].length} invitation(s) sent" if results[:created].any?
    messages << "#{results[:already_member].length} user(s) already members" if results[:already_member].any?
    messages << "#{results[:invalid].length} invalid email(s)" if results[:invalid].any?

    messages.join(", ").capitalize
  end
end
