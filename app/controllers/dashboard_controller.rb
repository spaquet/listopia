# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  before_action :authenticate_user!

  # Main dashboard view showing user's lists and recent activity
  def index
    # Remove unnecessary includes - use counter caches instead
    @my_lists = current_user.lists
                          .order(updated_at: :desc)
                          .limit(10)

    @collaborated_lists = current_user.collaborated_lists.includes(:owner)
                                    .order(updated_at: :desc)
                                    .limit(10)

    @recent_items = ListItem.joins(:list)
                          .where(list: current_user.accessible_lists)
                          .includes(:list) # Only include what we need
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
