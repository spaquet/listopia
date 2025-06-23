# app/controllers/application_controller.rb (Updated)
class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  protect_from_forgery with: :exception

  # Include authentication helpers
  include Authentication

  # Before actions
  before_action :authenticate_user!, except: [ :index, :show ] # Allow public access to some actions
  before_action :set_current_user

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

  # Global error handling
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActionController::Forbidden, with: :forbidden
end
