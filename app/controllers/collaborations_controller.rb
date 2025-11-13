# app/controllers/collaborations_controller.rb
class CollaborationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_collaboratable
  before_action :set_collaboration, only: [ :update, :destroy, :resend ]
  before_action :authorize_manage_collaborators!, except: [ :accept, :show, :index ]

  # GET /lists/:list_id/collaborations
  # GET /list_items/:list_item_id/collaborations
  # Show the share modal
  def index
    authorize @collaboratable, :manage_collaborators?, policy_class: get_policy_class

    @collaborators = @collaboratable.collaborators.includes(:user)
    @pending_invitations = @collaboratable.invitations.pending.includes(:invited_by)
    @can_manage_collaborators = can_manage_collaborators?(@collaboratable)
    @resource_type = @collaboratable.class.name
    @can_remove_collaborator = can_manage_collaborators?(@collaboratable)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "modal",
          partial: "collaborations/share_modal",
          locals: {
            resource: @collaboratable,
            resource_type: @resource_type,
            collaborators: @collaborators,
            pending_invitations: @pending_invitations,
            can_manage_collaborators: @can_manage_collaborators,
            can_remove_collaborator: @can_remove_collaborator
          }
        )
      end
    end
  end

  # GET /lists/:list_id/collaborations/:id
  # GET /list_items/:list_item_id/collaborations/:id
  # Show a specific collaboration (for detail view, if needed)
  def show
    authorize @collaboratable, :manage_collaborators?, policy_class: get_policy_class

    @collaborators = @collaboratable.collaborators.includes(:user)
    @pending_invitations = @collaboratable.invitations.pending.includes(:invited_by)
    @can_manage_collaborators = can_manage_collaborators?(@collaboratable)
    @resource_type = @collaboratable.class.name
    @can_remove_collaborator = can_manage_collaborators?(@collaboratable)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "modal",
          partial: "collaborations/share_modal",
          locals: {
            resource: @collaboratable,
            resource_type: @resource_type,
            collaborators: @collaborators,
            pending_invitations: @pending_invitations,
            can_manage_collaborators: @can_manage_collaborators,
            can_remove_collaborator: @can_remove_collaborator
          }
        )
      end
      format.html { render :show }
    end
  end

  # POST /lists/:list_id/collaborations
  # POST /list_items/:list_item_id/collaborations
  def create
    service = InvitationService.new(@collaboratable, current_user)

    # Extract role granting options
    grant_roles = {
      can_invite_collaborators: params[:can_invite_collaborators] == "1" || params[:can_invite_collaborators] == true
    }

    result = service.invite(
      collaboration_params[:email],
      collaboration_params[:permission],
      grant_roles
    )

    if result.success?
      respond_to do |format|
        format.html { redirect_to @collaboratable, notice: result.message }
        format.turbo_stream do
          # Reload associations to get fresh data
          @collaboratable.reload
          stream_updates = [
            turbo_stream.replace(
              "flash-messages",
              partial: "shared/flash_messages",
              locals: { notice: result.message }
            )
          ]
          if @collaboratable.collaborators.last
            stream_updates.unshift(
              turbo_stream.append(
                "collaborators-list",
                partial: "collaborations/collaborator",
                locals: { collaborator: @collaboratable.collaborators.last }
              )
            )
          end
          render turbo_stream: stream_updates
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to @collaboratable, alert: result.errors.join(", ") }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "flash-messages",
            partial: "shared/flash_messages",
            locals: { alert: result.errors.join(", ") }
          ), status: :unprocessable_entity
        end
      end
    end
  end

  # PATCH /lists/:list_id/collaborations/:id
  # PATCH /list_items/:list_item_id/collaborations/:id
  def update
    authorize @collaboration

    old_permission = @collaboration.permission

    if @collaboration.update(collaboration_params.slice(:permission))
      # Handle role changes
      if params[:can_invite_collaborators] == "1" || params[:can_invite_collaborators] == true
        @collaboration.add_role(:can_invite_collaborators) unless @collaboration.has_role?(:can_invite_collaborators)
      else
        @collaboration.remove_role(:can_invite_collaborators) if @collaboration.has_role?(:can_invite_collaborators)
      end

      CollaborationMailer.permission_updated(@collaboration, old_permission).deliver_later if old_permission != @collaboration.permission

      respond_to do |format|
        format.html { redirect_to @collaboratable, notice: "Permission updated successfully." }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            @collaboration,
            partial: "collaborations/collaborator",
            locals: { collaborator: @collaboration }
          )
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to @collaboratable, alert: @collaboration.errors.full_messages.join(", ") }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "flash-messages",
            partial: "shared/flash_messages",
            locals: { alert: @collaboration.errors.full_messages.join(", ") }
          ), status: :unprocessable_entity
        end
      end
    end
  end

  # DELETE /lists/:list_id/collaborations/:id
  # DELETE /list_items/:list_item_id/collaborations/:id
  def destroy
    authorize @collaboration

    is_invitation = @collaboration.is_a?(Invitation)
    user = @collaboration.is_a?(Collaborator) ? @collaboration.user : nil
    @collaboration.destroy

    CollaborationMailer.removed_from_resource(user, @collaboratable).deliver_later if user

    respond_to do |format|
      format.html { redirect_to @collaboratable, notice: "Collaborator removed successfully." }
      format.turbo_stream do
        # Refresh the modal to show updated collaborators/invitations list
        @collaborators = @collaboratable.collaborators.includes(:user)
        @pending_invitations = @collaboratable.invitations.pending.includes(:invited_by)
        @can_manage_collaborators = can_manage_collaborators?(@collaboratable)
        @resource_type = @collaboratable.class.name
        @can_remove_collaborator = can_manage_collaborators?(@collaboratable)

        render turbo_stream: turbo_stream.update(
          "modal",
          partial: "collaborations/share_modal",
          locals: {
            resource: @collaboratable,
            resource_type: @resource_type,
            collaborators: @collaborators,
            pending_invitations: @pending_invitations,
            can_manage_collaborators: @can_manage_collaborators,
            can_remove_collaborator: @can_remove_collaborator
          }
        )
      end
    end
  end

  # PATCH /lists/:list_id/collaborations/:id/resend
  # PATCH /list_items/:list_item_id/collaborations/:id/resend
  def resend
    # @collaboration here is actually an Invitation
    authorize @collaboration

    service = InvitationService.new(@collaboratable, current_user)
    result = service.resend(@collaboration)

    respond_to do |format|
      format.html { redirect_to @collaboratable, notice: result.message }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "flash-messages",
          partial: "shared/flash_messages",
          locals: { notice: result.message }
        )
      end
    end
  end

  # GET /lists/:list_id/collaborations/accept/:token
  # This is handled by InvitationsController#accept
  # Kept here for route consistency but redirects to main handler
  def accept
    redirect_to accept_invitation_url(token: params[:token])
  end

  private

  def set_collaboratable
    if params[:list_id]
      @collaboratable = List.find(params[:list_id])
    elsif params[:list_item_id]
      @collaboratable = ListItem.find(params[:list_item_id])
    else
      redirect_to root_path, alert: "Invalid collaboration resource."
    end
  end

  def set_collaboration
    # This could be a Collaborator or an Invitation depending on the action
    if action_name == "resend"
      @collaboration = @collaboratable.invitations.find(params[:id])
    elsif action_name == "destroy"
      # Try to find as Invitation first (pending), then as Collaborator
      @collaboration = @collaboratable.invitations.find_by(id: params[:id]) ||
                       @collaboratable.collaborators.find(params[:id])
    else
      @collaboration = @collaboratable.collaborators.find(params[:id])
    end
  end

  def authorize_manage_collaborators!
    authorize @collaboratable, :manage_collaborators?, policy_class: get_policy_class
  end

  def get_policy_class
    case @collaboratable
    when List
      ListPolicy
    when ListItem
      ListItemPolicy
    else
      ApplicationPolicy
    end
  end

  def can_manage_collaborators?(resource)
    policy(resource).manage_collaborators?
  rescue Pundit::NotAuthorizedError
    false
  end

  def collaboration_params
    params.require(:collaboration).permit(:email, :permission, :can_invite_collaborators)
  rescue ActionController::ParameterMissing
    # If params aren't wrapped in :collaboration key, try top-level params
    params.permit(:email, :permission, :can_invite_collaborators)
  end
end
