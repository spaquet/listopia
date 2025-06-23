# app/controllers/application_controller.rb
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

# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  before_action :authenticate_user!

  # Main dashboard view showing user's lists and recent activity
  def index
    @my_lists = current_user.lists.includes(:list_items, :collaborators)
                           .order(updated_at: :desc)
                           .limit(10)

    @collaborated_lists = current_user.collaborated_lists.includes(:owner, :list_items)
                                    .order(updated_at: :desc)
                                    .limit(10)

    @recent_items = ListItem.joins(:list)
                           .where(list: current_user.accessible_lists)
                           .order(updated_at: :desc)
                           .limit(20)

    @stats = calculate_dashboard_stats
  end

  private

  # Calculate statistics for dashboard display
  def calculate_dashboard_stats
    accessible_lists = current_user.accessible_lists

    {
      total_lists: accessible_lists.count,
      active_lists: accessible_lists.status_active.count,
      completed_lists: accessible_lists.status_completed.count,
      total_items: ListItem.joins(:list).where(list: accessible_lists).count,
      completed_items: ListItem.joins(:list).where(list: accessible_lists, completed: true).count,
      overdue_items: ListItem.joins(:list).where(list: accessible_lists)
                            .where("due_date < ? AND completed = false", Time.current).count
    }
  end
end
