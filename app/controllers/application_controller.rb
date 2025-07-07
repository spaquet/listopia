# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include Pundit::Authorization

  # Prevent outdated browsers from accessing the application
  # This is a security measure to ensure users are on modern browsers.
  # Associated resource: public/406-unsupported-browser.html
  allow_browser versions: :modern

  # Prevent CSRF attacks by raising an exception.
  protect_from_forgery with: :exception

  # Helper methods available in views
  helper_method :current_user, :user_signed_in?

  # Before actions
  before_action :set_current_user

  # AUTHENTICATION METHODS

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
    session[:user_signed_in_at] = Time.current.to_s  # Store as string
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

  # Pundit authorization
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  protected

  # Set current user for use in models and services
  def set_current_user
    Current.user = current_user if defined?(current_user)
  end

  # Authorization helper - check if user can access resource
  def authorize_resource_access!(resource, action = :read)
    unless can_access?(resource, action)
      redirect_to root_path, alert: "Access denied."
    end
  end

  # Handle Turbo Stream responses
  def respond_with_turbo_stream(&block)
    respond_to do |format|
      format.turbo_stream(&block) if block_given?
      format.html { redirect_back(fallback_location: root_path) }
    end
  end

  # Handle not found errors
  def not_found
    render file: "#{Rails.root}/public/404.html", layout: false, status: :not_found
  end

  # Handle forbidden errors
  def forbidden
    render file: "#{Rails.root}/public/403.html", layout: false, status: :forbidden
  end

  # Custom exception for forbidden access
  class ForbiddenError < StandardError; end

  # Global error handling
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ForbiddenError, with: :forbidden

  private

  # Store location for redirect after authentication
  def store_location
    session[:stored_location] = request.fullpath if request.get? && !request.xhr?
  end

  # Get stored location
  def stored_location
    session.delete(:stored_location)
  end

  # Check if session is expired (optional security feature)
  def session_expired?
    return false unless session[:user_signed_in_at]

    begin
      # Parse the stored time string back to Time object
      signed_in_at = Time.parse(session[:user_signed_in_at])
      # Sessions expire after 24 hours of inactivity
      Time.current > (signed_in_at + 24.hours)
    rescue ArgumentError, TypeError
      # If we can't parse the time, consider the session expired
      true
    end
  end

  # Authenticate user from session
  def authenticate_user_from_session
    return nil unless session[:user_id]
    return nil if session_expired?

    user = User.find_by(id: session[:user_id])

    if user&.email_verified?
      # Update session timestamp directly without calling user_signed_in?
      session[:user_signed_in_at] = Time.current.to_s
      user
    else
      reset_session
      nil
    end
  end

  # Handle unauthorized access
  # This method is called by Pundit when a user tries to access a resource they
  # are not authorized to access.
  def user_not_authorized
    flash[:alert] = "You are not authorized to perform this action."
    redirect_back(fallback_location: lists_path)
  end
end
