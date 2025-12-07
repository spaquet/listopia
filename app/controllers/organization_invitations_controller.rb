class OrganizationInvitationsController < ApplicationController
  before_action :authenticate_user!, except: [ :accept ]
  before_action :set_organization, except: [ :accept ]
  before_action :set_invitation, only: [ :show, :resend, :revoke ]
  before_action :authorize_access!, except: [ :accept ]

  def index
    authorize @organization, :invite_member?
    @pagy, @invitations = pagy(@organization.invitations.pending.order(created_at: :desc))
  end

  def show
    authorize @organization, :invite_member?
  end

  def accept
    token = params[:token]
    @invitation = Invitation.find_by_invitation_token(token)

    if @invitation.nil? || @invitation.organization.nil?
      redirect_to root_path, alert: "Invalid or expired invitation link."
      return
    end

    if @invitation.status != "pending"
      redirect_to root_path, alert: "This invitation is no longer valid."
      return
    end

    if user_signed_in?
      # User is already signed in
      if current_user.email == @invitation.email
        # Accept the invitation
        accept_organization_invitation(@invitation, current_user)
      else
        redirect_to sign_in_path, alert: "Please sign in with the email address #{@invitation.email} to accept this invitation."
      end
    else
      # User is not signed in - store token in session for later
      session[:pending_organization_invitation_token] = token
      session[:pending_organization_invitation_email] = @invitation.email
      redirect_to new_registration_path, notice: "Please sign up to accept the invitation to #{@invitation.organization.name}."
    end
  end

  def resend
    authorize @organization, :invite_member?

    if @invitation.update(invitation_sent_at: Time.current)
      CollaborationMailer.organization_invitation(@invitation).deliver_later
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

  def accept_organization_invitation(invitation, user)
    ActiveRecord::Base.transaction do
      # Create or update organization membership
      membership = invitation.organization.organization_memberships.find_or_create_by(user: user) do |m|
        m.role = invitation.metadata&.dig("role") || "member"
        m.status = :active
        m.joined_at = Time.current
      end

      # Update membership if it was suspended or pending
      if membership.status_suspended? || membership.status_revoked? || membership.status_pending?
        membership.update!(status: :active)
      end

      # Mark invitation as accepted
      invitation.update!(
        user: user,
        status: "accepted",
        invitation_accepted_at: Time.current
      )

      # Update user status to active once they accept invitation
      user.update!(
        current_organization_id: invitation.organization.id,
        status: "active"
      )
    end

    redirect_to organization_path(invitation.organization), notice: "You've successfully joined #{invitation.organization.name}!"
  rescue StandardError => e
    redirect_to root_path, alert: "Unable to accept invitation: #{e.message}"
  end
end
