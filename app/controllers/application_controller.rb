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
    unless current_user
      respond_to do |format|
        format.html { redirect_to sign_in_path, alert: "Please sign in to continue" }
        format.json { render json: { error: "Authentication required" }, status: :unauthorized }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash_messages"), status: :unauthorized }
      end
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
    Current.request_id = request.request_id if request.respond_to?(:request_id)
    Current.user_agent = request.user_agent if request.respond_to?(:user_agent)
    Current.ip_address = request.remote_ip if request.respond_to?(:remote_ip)
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

  def chat_context
    @chat_context ||= build_chat_context
  end
  helper_method :chat_context

  def build_chat_context
    context = {
      page: "#{controller_name}##{action_name}",
      current_page: "#{controller_name}##{action_name}"
    }

    # Add list-specific context if we're on a list page
    if defined?(@list) && @list.present?
      context.merge!(
        list_id: @list.id,
        list_title: @list.title,
        items_count: @list.list_items.count,
        completed_count: @list.list_items.where(status: :completed).count,
        is_owner: @list.user_id == current_user&.id,
        can_collaborate: @list.user_id == current_user&.id || @list.can_collaborate?(current_user)
      )
    end

    # Add user's total lists count
    if current_user.present?
      context[:total_lists] = current_user.accessible_lists.count
    end

    context
  end

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
