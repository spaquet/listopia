class OrganizationInvitationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization
  before_action :set_invitation, only: [:show, :resend, :revoke]
  before_action :authorize_access!

  def index
    authorize @organization, :invite_member?
    @pagy, @invitations = pagy(@organization.invitations.pending.order(created_at: :desc))
  end

  def show
    authorize @organization, :invite_member?
  end

  def resend
    authorize @organization, :invite_member?

    if @invitation.update(invitation_sent_at: Time.current)
      # TODO: Send invitation email here
      respond_to do |format|
        format.html { redirect_to organization_invitations_path(@organization), notice: "Invitation resent." }
        format.turbo_stream
      end
    else
      respond_to do |format|
        format.html { redirect_to organization_invitations_path(@organization), alert: "Unable to resend invitation." }
      end
    end
  end

  def revoke
    authorize @organization, :remove_member?

    if @invitation.update(status: :revoked)
      respond_to do |format|
        format.html { redirect_to organization_invitations_path(@organization), notice: "Invitation revoked." }
        format.turbo_stream { render action: :revoke }
      end
    else
      respond_to do |format|
        format.html { redirect_to organization_invitations_path(@organization), alert: "Unable to revoke invitation." }
      end
    end
  end

  private

  def set_organization
    @organization = Organization.find(params[:organization_id])
  end

  def set_invitation
    @invitation = @organization.invitations.find(params[:id])
  end

  def authorize_access!
    authorize @organization, :invite_member?
  end
end
