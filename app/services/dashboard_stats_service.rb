# app/services/dashboard_stats_service.rb
class DashboardStatsService
  def initialize(user, organization = nil)
    @user = user
    @organization = organization
  end

  def call
    accessible_lists = if @organization
                         @organization.lists.where(user_id: @user.id)
    else
                         @user.lists.where(organization_id: nil)
    end

    accessible_lists_ids = accessible_lists.pluck(:id)

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
