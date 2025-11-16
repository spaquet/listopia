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

    emails = params[:emails].split(/[\n,]/).map(&:strip).reject(&:blank?)
    role = params[:role] || 'member'

    emails.each do |email|
      next if email.blank?

      user = User.find_by(email: email)

      if user.present?
        # User exists, create membership directly or update if exists
        membership = @organization.organization_memberships.find_or_initialize_by(user: user)
        membership.role = role
        membership.status = :active
        membership.save
      else
        # User doesn't exist, create invitation
        @organization.invitations.create(
          invitable_type: 'Organization',
          invitable_id: @organization.id,
          email: email,
          role: role,
          invited_by: current_user
        )
      end
    end

    respond_to do |format|
      format.html { redirect_to organization_members_path(@organization), notice: "Invitations sent successfully." }
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
end
