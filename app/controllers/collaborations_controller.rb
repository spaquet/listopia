# app/controllers/collaborations_controller.rb
class CollaborationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_list
  before_action :authorize_list_owner!

  # Show collaboration management page
  def index
    @collaborations = @list.list_collaborations.includes(:user)
    @new_collaboration = @list.list_collaborations.build
  end

  # Add a new collaborator to the list
  def create
    email = params[:email]
    permission = params[:permission] || "read"

    user = User.find_by(email: email)

    if user.nil?
      # Send invitation email to non-registered user
      send_invitation_email(email, permission)
      flash[:notice] = "Invitation sent to #{email}"
    else
      # Add existing user as collaborator
      collaboration = @list.add_collaborator(user, permission: permission)

      if collaboration.persisted?
        # Send notification email
        CollaborationMailer.added_to_list(collaboration).deliver_later
        flash[:notice] = "#{user.name} has been added as a collaborator"
      else
        flash[:alert] = "Could not add collaborator"
      end
    end

    respond_with_turbo_stream do
      render :create
    end
  end

  # Update collaborator permissions
  def update
    @collaboration = @list.list_collaborations.find(params[:id])

    if @collaboration.update(collaboration_params)
      respond_with_turbo_stream do
        render :update
      end
    else
      respond_with_turbo_stream do
        render :form_errors
      end
    end
  end

  # Remove a collaborator from the list
  def destroy
    @collaboration = @list.list_collaborations.find(params[:id])
    user = @collaboration.user

    @collaboration.destroy

    # Send notification email
    CollaborationMailer.removed_from_list(user, @list).deliver_later

    respond_with_turbo_stream do
      render :destroy
    end
  end

  # Accept collaboration invitation
  def accept_invitation
    token = params[:token]
    collaboration = ListCollaboration.find_by(invitation_token: token)

    if collaboration && collaboration.invitation_accepted_at.nil?
      collaboration.update!(
        invitation_accepted_at: Time.current,
        user: current_user
      )

      redirect_to collaboration.list, notice: "You have joined the list!"
    else
      redirect_to root_path, alert: "Invalid or expired invitation."
    end
  end

  private

  # Find the list ensuring user is the owner
  def set_list
    @list = current_user.lists.find(params[:list_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to lists_path, alert: "List not found."
  end

  # Ensure only list owner can manage collaborations
  def authorize_list_owner!
    redirect_to @list, alert: "Only the list owner can manage collaborations." unless @list.owner == current_user
  end

  # Strong parameters for collaboration updates
  def collaboration_params
    params.require(:list_collaboration).permit(:permission)
  end

  # Send invitation email to non-registered users
  def send_invitation_email(email, permission)
    invitation_token = SecureRandom.urlsafe_base64(32)

    # Store invitation in session or database for later processing
    Rails.cache.write(
      "invitation_#{invitation_token}",
      {
        email: email,
        list_id: @list.id,
        permission: permission,
        invited_by: current_user.id
      },
      expires_in: 7.days
    )

    # Send invitation email
    CollaborationMailer.invitation(email, @list, current_user, invitation_token).deliver_later
  end
end
