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
    # Get the accessible lists as actual records, not grouped results
    accessible_lists_ids = current_user.accessible_lists.pluck(:id)

    # Use the IDs to build proper queries
    accessible_lists = List.where(id: accessible_lists_ids)

    {
      total_lists: accessible_lists.count,
      active_lists: accessible_lists.status_active.count,
      completed_lists: accessible_lists.status_completed.count,
      total_items: ListItem.joins(:list).where(list_id: accessible_lists_ids).count,
      completed_items: ListItem.joins(:list).where(list_id: accessible_lists_ids, completed: true).count,
      overdue_items: ListItem.joins(:list).where(list_id: accessible_lists_ids)
                            .where("due_date < ? AND completed = false", Time.current).count
    }
  end
end
