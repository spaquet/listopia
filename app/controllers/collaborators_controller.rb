# app/controllers/collaborators_controller.rb
class CollaboratorsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_collaboratable
  before_action :set_collaborator, only: [ :show, :update, :destroy ]

  def index
    authorize Collaborator.new(collaboratable: @collaboratable)
    @collaborators = @collaboratable.collaborators.includes(:user)
    @invitations = @collaboratable.invitations.pending.includes(:invited_by)
  end

  def create
    @collaborator = @collaboratable.collaborators.build(collaborator_params)
    @collaborator.user = User.find_by(email: params[:email]) if params[:email].present?

    authorize @collaborator

    if @collaborator.user
      # Direct collaboration for existing user
      if @collaborator.save
        send_collaboration_notification(@collaborator)
        redirect_to collaborators_path, notice: "Collaborator added successfully!"
      else
        @collaborators = @collaboratable.collaborators.includes(:user)
        @invitations = @collaboratable.invitations.pending
        render :index, status: :unprocessable_entity
      end
    else
      # Create invitation for non-existing user
      invitation_service = InvitationService.new(@collaboratable, current_user)
      result = invitation_service.invite(params[:email], collaborator_params[:permission])

      if result.success?
        redirect_to collaborators_path, notice: "Invitation sent successfully!"
      else
        flash.now[:alert] = result.errors.join(", ")
        @collaborators = @collaboratable.collaborators.includes(:user)
        @invitations = @collaboratable.invitations.pending
        render :index, status: :unprocessable_entity
      end
    end
  end

  def update
    authorize @collaborator

    if @collaborator.update(collaborator_params)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace(@collaborator, @collaborator) }
        format.html { redirect_to collaborators_path, notice: "Permission updated!" }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace(@collaborator, @collaborator) }
        format.html { redirect_to collaborators_path, alert: "Failed to update permission." }
      end
    end
  end

  def destroy
    authorize @collaborator

    @collaborator.destroy
    send_removal_notification(@collaborator.user) if @collaborator.user

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@collaborator) }
      format.html { redirect_to collaborators_path, notice: "Collaborator removed!" }
    end
  end

  private

  def set_collaboratable
    if params[:list_id]
      @collaboratable = List.find(params[:list_id])
    elsif params[:list_item_id]
      @collaboratable = ListItem.find(params[:list_item_id])
    else
      redirect_to lists_path, alert: "Invalid resource."
    end
  end

  def set_collaborator
    @collaborator = @collaboratable.collaborators.find(params[:id])
  end

  def collaborator_params
    params.require(:collaborator).permit(:permission)
  end

  def send_collaboration_notification(collaborator)
    CollaborationMailer.added_to_resource(collaborator).deliver_later
  end

  def send_removal_notification(user)
    CollaborationMailer.removed_from_resource(user, @collaboratable).deliver_later
  end
end
