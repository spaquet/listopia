# app/controllers/invitations_controller.rb
class InvitationsController < ApplicationController
  before_action :authenticate_user!, except: [ :accept ]
  before_action :set_invitation, only: [ :show, :destroy, :resend ]

  def accept
    @invitation = Invitation.find_by_invitation_token(params[:token])

    unless @invitation
      redirect_to root_path, alert: "Invalid or expired invitation link."
      return
    end

    authorize @invitation

    if current_user
      if @invitation.accept!(current_user)
        redirect_to @invitation.invitable, notice: "You have successfully accepted the invitation!"
      else
        redirect_to @invitation.invitable, alert: "This invitation was sent to a different email address."
      end
    else
      session[:pending_invitation_token] = params[:token]
      redirect_to new_registration_path, notice: "Please sign up or log in to accept this invitation."
    end
  end

  def destroy
    authorize @invitation

    @invitation.destroy

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@invitation) }
      format.html { redirect_back(fallback_location: root_path, notice: "Invitation cancelled.") }
    end
  end

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
end
