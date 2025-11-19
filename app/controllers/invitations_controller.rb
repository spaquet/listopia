# app/controllers/invitations_controller.rb

#
# === InvitationsController Documentation ===
#
# PURPOSE
#   Unified controller handling two distinct invitation types within a single resource.
#   This approach reuses existing infrastructure and maintains a single source of truth
#   for invitation management, rather than creating separate controllers.
#
# INVITATION TYPES
#   1. Platform Invitations (invitable_type: "User")
#      - Admin invites users to join the Listopia application
#      - Handled by: accept_platform_invitation
#      - Uses: @invitation.accept!(current_user) - instance method on Invitation model
#      - Result: User gains platform access
#
#   2. Collaboration Invitations (invitable_type: "List" or "ListItem")
#      - Users invite collaborators to work on specific resources
#      - Handled by: accept_collaboration_invitation
#      - Uses: CollaborationAcceptanceService.accept(current_user) - service layer
#      - Result: Creates Collaborator record with permission/roles, triggers notifications
#
# ARCHITECTURE PRINCIPLES
#   - Single responsibility: This controller handles all invitation acceptance flows
#   - Context-aware routing: Private methods route based on invitable_type
#   - Service layer: Complex collaboration logic delegated to CollaborationAcceptanceService
#   - Reusable patterns: Both flows use same authorization (Pundit), session management, and responses
#   - Email verification: Both flows verify email match before acceptance
#
# AUTHORIZATION FLOW
#   - All actions protected by Pundit policies (InvitationPolicy)
#   - accept? policy: Checks if current_user.email matches invitation.email
#   - destroy?, resend?: Check ownership (invited_by or resource owner)
#   - Works uniformly across both invitation types
#
# SESSION MANAGEMENT
#   - pending_invitation_token stored in session for unauthenticated users
#   - Used to auto-accept invitation after signup/login
#   - Cleared after successful acceptance to prevent replay
#   - Pattern reused from admin authentication flow
#
# RESPONSE FORMATS
#   - HTML: Traditional redirects with flash messages
#   - Turbo Stream: Real-time updates for collaboration UI (when available)
#   - Both formats supported for seamless UX across devices
#
# SECURITY CONSIDERATIONS
#   - Token validation: Invitations found via Rails 8's generates_token_for (signed tokens)
#   - Email matching: Strict validation that accepting user's email matches invitation email
#   - Status tracking: Prevents accepting already-accepted or expired invitations
#   - Expiration: Collaboration invites expire after 7 days (set in migrations/services)
#
# FAILURE HANDLING
#   - Invalid/expired tokens: Redirect to root with alert
#   - Email mismatch: Alert user and suggest logging in with correct email
#   - Service failures: CollaborationAcceptanceService returns detailed error messages
#   - Turbo Stream errors: Unprocessable entity response with error partial
#
# INTEGRATION POINTS
#   - RegistrationsController: Handles post-signup invitation acceptance (session token flow)
#   - SessionsController: Handles post-login invitation acceptance (session token flow)
#   - CollaborationAcceptanceService: Creates Collaborator, assigns roles, updates invitation status
#   - InvitationService: Resends invitation emails for both types
#   - CollaborationMailer: Sends notifications for collaboration invitations
#
# NEW: INDEX ACTION (List Sent & Received Invitations)
#   - index: Lists invitations sent by current user (with management options) and received by current user
#   - Uses turbo_stream format for search/filter without page reload
#   - Sent tab: Shows pending/active invitations with options to revoke, resend, or update permissions
#   - Received tab: Shows pending invitations with options to accept or decline
#   - Supports filtering by: tab (sent/received), status (pending/accepted/expired), search by email/name/list
#   - Uses Stimulus controller (invitation-filter) for real-time filter updates with focus retention
#
# EXTENDING THIS CONTROLLER
#   - To add new invitation types: Add case statement in accept() and create new private handler method
#   - To add new actions: Follow same pattern (check type, route to specialized private method)
#   - To modify behavior: Update relevant private method or service layer, not the public API
#
# RELATED FILES
#   - app/models/invitation.rb - Data model with validations and token generation
#   - app/policies/invitation_policy.rb - Pundit authorization rules
#   - app/services/collaboration_acceptance_service.rb - Complex collaboration acceptance logic
#   - app/services/invitation_service.rb - Invitation creation and resending
#   - app/mailers/collaboration_mailer.rb - Email notifications
class InvitationsController < ApplicationController
  before_action :authenticate_user!, except: [ :accept ]
  before_action :set_invitation, only: [ :show, :destroy, :resend, :revoke, :update, :decline ]

  # GET /invitations
  # List sent and received collaboration invitations with filtering and search
  def index
    # Determine which tab to show
    @tab = params[:tab] || "received"

    if @tab == "sent"
      # Sent invitations - those created by current user (excluding accepted)
      @invitations = current_user.sent_invitations
                                  .where(invitable_type: [ "List", "ListItem" ])
                                  .where.not(status: "accepted")
                                  .includes(:invitable, :user)
    else
      # Received invitations - those sent to current user (only pending)
      @invitations = current_user.received_invitations
                                  .where(invitable_type: [ "List", "ListItem" ])
                                  .where(status: "pending")
                                  .includes(:invitable, :invited_by)
    end

    # Apply search filter
    if params[:search].present?
      search_term = "%#{params[:search].strip}%"
      @invitations = @invitations.joins(
        "LEFT JOIN users ON invitations.#{@tab == 'sent' ? 'user_id' : 'invited_by_id'} = users.id"
      ).joins(
        "LEFT JOIN lists ON invitations.invitable_id = lists.id AND invitations.invitable_type = 'List'"
      ).where(
        "invitations.email ILIKE ? OR users.email ILIKE ? OR users.name ILIKE ? OR lists.title ILIKE ?",
        search_term, search_term, search_term, search_term
      ).distinct
    end

    # Apply status filter
    if params[:status].present?
      @invitations = @invitations.where(status: params[:status])
    end

    # Order by created_at descending
    @invitations = @invitations.order(created_at: :desc)

    # Store current filters for view
    @current_filters = {
      tab: @tab,
      search: params[:search],
      status: params[:status]
    }

    respond_to do |format|
      format.html
      format.turbo_stream do
        render :index
      end
    end
  end

  # GET /invitations/:token
  # Display invitation details (for collaboration invites)
  def show
    unless @invitation
      redirect_to root_path, alert: "Invalid or expired invitation link."
      return
    end

    if @invitation.status == "accepted"
      redirect_to @invitation.invitable, notice: "This invitation has already been accepted."
      return
    end

    if @invitation.status == "expired"
      redirect_to root_path, alert: "This invitation has expired."
      return
    end

    authorize @invitation
  end

  # POST/GET /invitations/:token/accept
  def accept
    @invitation = Invitation.find_by_invitation_token(params[:token])

    unless @invitation
      redirect_to root_path, alert: "Invalid or expired invitation link."
      return
    end

    authorize @invitation

    if current_user
      # Route based on invitable type
      case @invitation.invitable_type
      when "User"
        # Admin invitation to join platform
        accept_platform_invitation
      when "List", "ListItem"
        # Collaboration invitation
        accept_collaboration_invitation
      when "Team"
        # Team invitation
        accept_team_invitation
      else
        redirect_to root_path, alert: "Unknown invitation type."
      end
    else
      session[:pending_invitation_token] = params[:token]
      redirect_to new_registration_path, notice: "Please sign up or log in to accept this invitation."
    end
  end

  # DELETE /invitations/:id
  def destroy
    authorize @invitation

    # Store the ID before destroying
    invitation_id = @invitation.id

    @invitation.destroy

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove("invitation_#{invitation_id}") }
      format.html { redirect_back(fallback_location: root_path, notice: "Invitation cancelled.") }
    end
  end

  # PATCH /invitations/:id/resend
  def resend
    authorize @invitation

    InvitationService.new(@invitation.invitable, current_user).resend(@invitation)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "invitation_#{@invitation.id}",
          partial: "invitation",
          locals: { invitation: @invitation, is_sent: @invitation.invited_by == current_user }
        )
      end
      format.html { redirect_back(fallback_location: root_path, notice: "Invitation resent.") }
    end
  end

  # PATCH /invitations/:id/decline
  # Decline a received collaboration invitation
  def decline
    authorize @invitation

    unless @invitation.invited_by.present? && @invitation.email.present?
      respond_to do |format|
        format.html { redirect_to invitations_path, alert: "Invalid invitation." }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "flash-messages",
            partial: "shared/flash_message",
            locals: { message: "Invalid invitation.", type: "alert" }
          )
        }
      end
      return
    end

    if @invitation.update(status: "declined")
      respond_to do |format|
        format.html { redirect_to invitations_path(tab: "received"), notice: "Invitation declined." }
        format.turbo_stream do
          render turbo_stream: turbo_stream.remove("invitation_#{@invitation.id}")
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to invitations_path, alert: "Failed to decline invitation." }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "flash-messages",
            partial: "shared/flash_message",
            locals: { message: "Failed to decline invitation.", type: "alert" }
          )
        }
      end
    end
  end

  # DELETE /invitations/:id/revoke
  # Revoke a sent collaboration invitation
  def revoke
    authorize @invitation

    unless @invitation.invited_by == current_user
      respond_to do |format|
        format.html { redirect_to invitations_path, alert: "You cannot revoke this invitation." }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "flash-messages",
            partial: "shared/flash_message",
            locals: { message: "You cannot revoke this invitation.", type: "alert" }
          )
        }
      end
      return
    end

    if @invitation.update(status: "revoked")
      respond_to do |format|
        format.html { redirect_to invitations_path(tab: "sent"), notice: "Invitation revoked." }
        format.turbo_stream do
          render turbo_stream: turbo_stream.remove("invitation_#{@invitation.id}")
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to invitations_path, alert: "Failed to revoke invitation." }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "flash-messages",
            partial: "shared/flash_message",
            locals: { message: "Failed to revoke invitation.", type: "alert" }
          )
        }
      end
    end
  end

  # PATCH /invitations/:id
  # Update invitation permissions (sent invitations only)
  def update
    authorize @invitation

    unless @invitation.invited_by == current_user
      respond_to do |format|
        format.html { redirect_to invitations_path, alert: "You cannot update this invitation." }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "flash-messages",
            partial: "shared/flash_message",
            locals: { message: "You cannot update this invitation.", type: "alert" }
          )
        }
      end
      return
    end

    if @invitation.update(invitation_params)
      respond_to do |format|
        format.html { redirect_to invitations_path(tab: "sent"), notice: "Invitation updated." }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "invitation_#{@invitation.id}",
            partial: "invitation",
            locals: { invitation: @invitation, is_sent: true }
          )
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to invitations_path, alert: "Failed to update invitation." }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "flash-messages",
            partial: "shared/flash_message",
            locals: { message: "Failed to update invitation.", type: "alert" }
          )
        }
      end
    end
  end

  private

  def set_invitation
    @invitation = Invitation.find(params[:id])
  end

  # Handle admin platform invitations
  def accept_platform_invitation
    if @invitation.accept!(current_user)
      session.delete(:pending_invitation_token)
      redirect_to @invitation.invitable, notice: "You have successfully accepted the invitation!"
    else
      redirect_to root_path, alert: "This invitation was sent to a different email address."
    end
  end

  # Handle collaboration resource invitations
  def accept_collaboration_invitation
    # Verify email match
    unless current_user.email == @invitation.email
      redirect_to root_path, alert: "This invitation is for #{@invitation.email}, but you're logged in as #{current_user.email}."
      return
    end

    service = CollaborationAcceptanceService.new(@invitation)
    result = service.accept(current_user)

    if result.success?
      session.delete(:pending_invitation_token)

      respond_to do |format|
        format.html { redirect_to result.resource, notice: result.message }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("invitation", partial: "accepted") }
      end
    else
      respond_to do |format|
        format.html { redirect_to root_path, alert: result.errors.join(", ") }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("invitation", partial: "error", locals: { error: result.errors.join(", ") }), status: :unprocessable_entity }
      end
    end
  end

  # Handle team member invitations
  def accept_team_invitation
    # Verify email match
    unless current_user.email == @invitation.email
      redirect_to root_path, alert: "This invitation is for #{@invitation.email}, but you're logged in as #{current_user.email}."
      return
    end

    # Get the team from the invitation
    team = @invitation.invitable

    # Verify user is a member of the organization
    org_membership = team.organization.organization_memberships.find_by(user: current_user)
    unless org_membership
      redirect_to root_path, alert: "You must be a member of the organization to join this team."
      return
    end

    # Get the role from invitation metadata, default to 'member'
    role = @invitation.metadata['role'] || 'member'

    # Check if user is already a team member
    if team.member?(current_user)
      session.delete(:pending_invitation_token)
      redirect_to organization_team_path(team.organization, team), notice: "You are already a member of this team."
      return
    end

    # Create team membership
    team_membership = TeamMembership.new(
      team: team,
      user: current_user,
      organization_membership: org_membership,
      role: role
    )

    if team_membership.save
      # Mark invitation as accepted
      @invitation.update(
        user: current_user,
        status: 'accepted',
        invitation_accepted_at: Time.current
      )

      session.delete(:pending_invitation_token)
      redirect_to organization_team_path(team.organization, team), notice: "You have successfully joined the team!"
    else
      redirect_to root_path, alert: "Unable to join team: #{team_membership.errors.full_messages.join(', ')}"
    end
  end

  def invitation_params
    params.require(:invitation).permit(:permission)
  end
end
