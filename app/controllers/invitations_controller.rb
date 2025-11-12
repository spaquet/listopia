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
  before_action :set_invitation, only: [ :show, :destroy, :resend ]

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

    @invitation.destroy

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@invitation) }
      format.html { redirect_back(fallback_location: root_path, notice: "Invitation cancelled.") }
    end
  end

  # PATCH /invitations/:id/resend
  def resend
    authorize @invitation

    InvitationService.new(@invitation.invitable, current_user).resend(@invitation)

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace(@invitation, @invitation) }
      format.html { redirect_back(fallback_location: root_path, notice: "Invitation resent.") }
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
end
