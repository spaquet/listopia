# app/controllers/sessions_controller.rb
class SessionsController < ApplicationController
  before_action :redirect_if_authenticated, except: [ :destroy ]

  # Show login form
  def new
    @user = User.new
  end

  # Handle login
  def create
    @user = User.find_by(email: params[:email])

    if @user&.authenticate(params[:password])
      if @user.email_verified?
        sign_in(@user)

        # Check for pending collaboration invitation
        redirect_path = check_pending_collaboration || after_sign_in_path
        redirect_to redirect_path, notice: "Welcome back!"
      else
        redirect_to verify_email_path, alert: "Please verify your email address first."
      end
    else
      @user = User.new(email: params[:email]) # For form redisplay
      flash.now[:alert] = "Invalid email or password"
      render :new, status: :unprocessable_entity
    end
  end

  # Handle logout
  def destroy
    sign_out
    redirect_to root_path, notice: "You have been signed out."
  end

  # Send magic link
  def magic_link
    email = params[:email]
    user = User.find_by(email: email)

    if user
      begin
        magic_link_token = user.generate_magic_link_token
        AuthMailer.magic_link(user, magic_link_token).deliver_now
        redirect_to magic_link_sent_path, notice: "Magic link sent to your email!"
      rescue => e
        Rails.logger.error "Magic link generation failed: #{e.message}"
        flash.now[:alert] = "Failed to send magic link. Please try again."
        render :new, status: :unprocessable_entity
      end
    else
      flash.now[:alert] = "No account found with that email address."
      render :new, status: :unprocessable_entity
    end
  end

  # Handle magic link authentication
  def authenticate_magic_link
    token = params[:token]

    begin
      user = User.find_by_magic_link_token(token)

      if user
        sign_in(user)

        # Check for pending collaboration invitation
        redirect_path = check_pending_collaboration || after_sign_in_path
        redirect_to redirect_path, notice: "Successfully signed in!"
      else
        redirect_to new_session_path, alert: "Invalid or expired magic link."
      end
    rescue => e
      Rails.logger.error "Magic link authentication failed: #{e.message}"
      redirect_to new_session_path, alert: "Invalid or expired magic link."
    end
  end

  # Show magic link sent confirmation
  def magic_link_sent
    # Just render the template
  end

  private

  # Redirect authenticated users away from auth pages
  def redirect_if_authenticated
    redirect_to dashboard_path if current_user
  end

  # Check for pending collaboration and accept it
  def check_pending_collaboration
    return nil unless session[:pending_collaboration_token]

    collaboration = ListCollaboration.find_by_invitation_token(session[:pending_collaboration_token])
    if collaboration && collaboration.email == current_user.email
      collaboration.update!(user: current_user, email: nil)
      session.delete(:pending_collaboration_token)
      return collaboration.list # Redirect to the collaboration list
    end

    nil
  end
end
