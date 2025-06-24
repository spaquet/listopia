# app/controllers/collaborations_controller.rb
class CollaborationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_list, except: [ :accept ]
  before_action :ensure_list_owner, except: [ :index, :show, :accept ]
  before_action :set_collaboration, only: [ :show, :update, :destroy ]

  def index
    @collaborations = @list.list_collaborations.includes(:user)
    @new_collaboration = @list.list_collaborations.build

    respond_to do |format|
      format.html { render layout: false } # This will render without layout for turbo frame
      format.turbo_stream
    end
  end

  def create
    @collaboration = @list.list_collaborations.build(collaboration_params)

    # Try to find existing user by email
    user = User.find_by(email: @collaboration.email)
    if user
      @collaboration.user = user
      @collaboration.email = nil # Clear email since we have the user
    end

    respond_to do |format|
      if @collaboration.save
        # Send invitation email
        if user.nil?
          # Generate invitation token using Rails 8 method
          invitation_token = @collaboration.generate_invitation_token
          CollaborationMailer.invitation(@collaboration.email, @list, current_user, invitation_token).deliver_later
        else
          CollaborationMailer.added_to_list(@collaboration).deliver_later
        end

        format.turbo_stream {
          render turbo_stream: [
            turbo_stream.prepend("collaborations_list", partial: "collaborations/collaboration", locals: { collaboration: @collaboration }),
            turbo_stream.replace("new_collaboration_form", partial: "collaborations/new_form", locals: { list: @list, collaboration: @list.list_collaborations.build }),
            turbo_stream.replace("collaboration_stats", partial: "collaborations/stats", locals: { list: @list })
          ]
        }
        format.html { redirect_to list_collaborations_path(@list), notice: "Collaborator invited successfully!" }
      else
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace("new_collaboration_form", partial: "collaborations/new_form", locals: { list: @list, collaboration: @collaboration })
        }
        format.html {
          @collaborations = @list.list_collaborations.includes(:user)
          render :index
        }
      end
    end
  end

  def update
    respond_to do |format|
      if @collaboration.update(collaboration_params.except(:email))
        format.turbo_stream {
          render turbo_stream: [
            turbo_stream.replace("collaboration_#{@collaboration.id}", partial: "collaborations/collaboration", locals: { collaboration: @collaboration }),
            turbo_stream.replace("collaboration_stats", partial: "collaborations/stats", locals: { list: @list })
          ]
        }
        format.html { redirect_to list_collaborations_path(@list), notice: "Collaboration updated successfully!" }
      else
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace("collaboration_#{@collaboration.id}", partial: "collaborations/collaboration", locals: { collaboration: @collaboration })
        }
        format.html {
          @collaborations = @list.list_collaborations.includes(:user)
          render :index
        }
      end
    end
  end

  def destroy
    user = @collaboration.user
    @collaboration.destroy

    # Send notification email if user was registered
    if user
      CollaborationMailer.removed_from_list(user, @list).deliver_later
    end

    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: [
          turbo_stream.remove("collaboration_#{@collaboration.id}"),
          turbo_stream.replace("collaboration_stats", partial: "collaborations/stats", locals: { list: @list })
        ]
      }
      format.html { redirect_to list_collaborations_path(@list), notice: "Collaborator removed successfully!" }
    end
  end

  def accept
    @collaboration = ListCollaboration.find_by_invitation_token(params[:token])

    unless @collaboration
      redirect_to root_path, alert: "Invalid or expired invitation link."
      return
    end

    @list = @collaboration.list

    if current_user
      if @collaboration.email == current_user.email
        @collaboration.update!(user: current_user, email: nil)
        redirect_to @list, notice: "You have successfully joined the collaboration!"
      else
        redirect_to @list, alert: "This invitation was sent to a different email address."
      end
    else
      # Store the token in session and redirect to sign up/login
      session[:pending_collaboration_token] = params[:token]
      redirect_to new_registration_path, notice: "Please sign up or log in to accept this collaboration invitation."
    end
  end

  private

  def set_list
    @list = current_user.lists.find(params[:list_id])
  rescue ActiveRecord::RecordNotFound
    # Also check if user is a collaborator
    collaboration = current_user.list_collaborations.find_by(list_id: params[:list_id])
    if collaboration
      @list = collaboration.list
    else
      redirect_to lists_path, alert: "List not found."
    end
  end

  def set_collaboration
    @collaboration = @list.list_collaborations.find(params[:id])
  end

  def ensure_list_owner
    unless @list.owner == current_user
      redirect_to @list, alert: "You can only manage collaborations for your own lists."
    end
  end

  def collaboration_params
    params.require(:list_collaboration).permit(:email, :permission)
  end
end
