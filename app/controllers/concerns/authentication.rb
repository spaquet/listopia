# app/controllers/concerns/authentication.rb
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :current_user
    helper_method :current_user, :user_signed_in?
  end

  private

  # Get the current user from the session
  def current_user
    @current_user ||= authenticate_user_from_session
  end

  # Check if a user is signed in
  def user_signed_in?
    current_user.present?
  end

  # Require user to be authenticated
  def authenticate_user!
    unless user_signed_in?
      store_location
      redirect_to new_session_path, alert: "Please sign in to continue."
    end
  end

  # Sign in a user
  def sign_in(user)
    reset_session # Prevent session fixation attacks
    session[:user_id] = user.id
    session[:user_signed_in_at] = Time.current
    @current_user = user
  end

  # Sign out the current user
  def sign_out
    reset_session
    @current_user = nil
  end

  # Redirect after sign in
  def after_sign_in_path
    stored_location || dashboard_path
  end

  # Store location for redirect after authentication
  def store_location
    session[:stored_location] = request.fullpath if request.get? && !request.xhr?
  end

  # Get stored location
  def stored_location
    session.delete(:stored_location)
  end

  # Resume session helper
  def resume_session
    session[:user_signed_in_at] = Time.current if user_signed_in?
  end

  # Check if session is expired (optional security feature)
  def session_expired?
    return false unless session[:user_signed_in_at]

    # Sessions expire after 24 hours of inactivity
    Time.current > (session[:user_signed_in_at] + 24.hours)
  end

  # Authenticate user from session
  def authenticate_user_from_session
    return nil unless session[:user_id]
    return nil if session_expired?

    user = User.find_by(id: session[:user_id])

    if user&.email_verified?
      resume_session
      user
    else
      reset_session
      nil
    end
  end

  # For API authentication (future use)
  def authenticate_user_from_token
    return nil unless request.headers["Authorization"]

    token = request.headers["Authorization"].split(" ").last
    return nil unless token

    # Implement JWT or API token authentication here
    # This is a placeholder for future API authentication
    nil
  end

  # Ensure user owns resource or has permission
  def authorize_user!(resource)
    unless resource.respond_to?(:user) && resource.user == current_user
      redirect_to root_path, alert: "Access denied."
    end
  end

  # Check if current user can access resource
  def can_access?(resource, action = :read)
    return false unless current_user

    case resource
    when List
      case action
      when :read
        resource.readable_by?(current_user)
      when :edit, :update, :destroy
        resource.collaboratable_by?(current_user)
      else
        false
      end
    when ListItem
      can_access?(resource.list, action)
    else
      false
    end
  end
end
