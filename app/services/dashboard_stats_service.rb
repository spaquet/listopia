# app/services/dashboard_stats_service.rb
class DashboardStatsService
  def initialize(user, organization = nil)
    @user = user
    @organization = organization
  end

  def call
    # Count lists owned by the user (all owned lists for stats purposes)
    # user.lists association returns lists where user is the owner (via owner_id FK)
    owned_lists = if @organization
                    @user.lists.where(organization_id: @organization.id)
    else
                    @user.lists.where(organization_id: nil)
    end

    owned_lists_ids = owned_lists.pluck(:id)

    # Count lists where user is a collaborator (excluding public lists)
    # A list is public if it has is_public: true
    # We only count private lists that have been explicitly shared with the user
    collaborated_lists = if @organization
                          @user.collaborated_lists.where(organization_id: @organization.id, is_public: false)
    else
                          @user.collaborated_lists.where(organization_id: nil, is_public: false)
    end

    collaborated_lists_ids = collaborated_lists.pluck(:id)

    {
      owned_lists: owned_lists.count,
      collaborated_lists: collaborated_lists.count,
      total_lists: owned_lists.count + collaborated_lists.count,
      active_lists: owned_lists.status_active.count,
      completed_lists: owned_lists.status_completed.count,
      total_items: ListItem.where(list_id: owned_lists_ids).count,
      completed_items: ListItem.where(list_id: owned_lists_ids).completed.count,
      overdue_items: ListItem.where(list_id: owned_lists_ids)
                            .where("list_items.due_date < ? AND list_items.status != ?", Time.current, 2)
                            .count
    }
  end
end
