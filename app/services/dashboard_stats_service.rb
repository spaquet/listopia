# app/services/dashboard_stats_service.rb
class DashboardStatsService
  def initialize(user)
    @user = user
  end

  def call
    accessible_lists_ids = @user.accessible_lists.pluck(:id)
    accessible_lists = List.where(id: accessible_lists_ids)

    {
      total_lists: accessible_lists.count,
      active_lists: accessible_lists.status_active.count,
      completed_lists: accessible_lists.status_completed.count,
      total_items: ListItem.where(list_id: accessible_lists_ids).count,
      completed_items: ListItem.where(list_id: accessible_lists_ids).completed.count,
      overdue_items: ListItem.where(list_id: accessible_lists_ids)
                            .where("list_items.due_date < ? AND list_items.status != ?", Time.current, 2)
                            .count
    }
  end
end
