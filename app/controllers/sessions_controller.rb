# app/controllers/sessions_controller.rb
class SessionsController < ApplicationController
  skip_before_action :authenticate_user!
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
        redirect_to after_sign_in_path, notice: "Welcome back!"
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
      magic_link = user.generate_magic_link_token
      AuthMailer.magic_link(user, magic_link).deliver_now
      redirect_to magic_link_sent_path, notice: "Magic link sent to your email!"
    else
      flash.now[:alert] = "No account found with that email address."
      render :new, status: :unprocessable_entity
    end
  end

  # Handle magic link authentication
  def authenticate_magic_link
    token = params[:token]
    magic_link = MagicLink.find_valid_by_token(token)

    if magic_link
      magic_link.use!
      sign_in(magic_link.user)
      redirect_to after_sign_in_path, notice: "Successfully signed in!"
    else
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
end
