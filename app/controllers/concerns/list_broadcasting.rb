# app/controllers/concerns/list_broadcasting.rb
module ListBroadcasting
  extend ActiveSupport::Concern

  private

  # Helper method to get updated dashboard data
  def dashboard_data_for_user(user)
    {
      my_lists: user.lists.includes(:list_items, :collaborators).order(updated_at: :desc).limit(10),
      collaborated_lists: user.collaborated_lists.includes(:owner, :list_items).order(updated_at: :desc).limit(10),
      recent_items: ListItem.joins(:list).where(list: user.accessible_lists).order(updated_at: :desc).limit(20),
      stats: calculate_dashboard_stats_for_user(user)
    }
  end

  # Calculate statistics for dashboard display
  def calculate_dashboard_stats_for_user(user)
    accessible_lists = user.accessible_lists

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

  # Update dashboard for all affected users
  def broadcast_dashboard_updates(list = @list)
    # Update dashboard for list owner
    owner_data = dashboard_data_for_user(list.owner)

    Turbo::StreamsChannel.broadcast_replace_to(
      "user_dashboard_#{list.owner.id}",
      target: "dashboard-stats",
      partial: "dashboard/stats_overview",
      locals: { stats: owner_data[:stats] }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      "user_dashboard_#{list.owner.id}",
      target: "dashboard-my-lists",
      partial: "dashboard/my_lists",
      locals: { lists: owner_data[:my_lists] }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      "user_dashboard_#{list.owner.id}",
      target: "dashboard-recent-activity",
      partial: "dashboard/recent_activity",
      locals: { items: owner_data[:recent_items] }
    )

    # Update dashboard for collaborators
    list.collaborators.each do |collaborator|
      collaborator_data = dashboard_data_for_user(collaborator)

      Turbo::StreamsChannel.broadcast_replace_to(
        "user_dashboard_#{collaborator.id}",
        target: "dashboard-stats",
        partial: "dashboard/stats_overview",
        locals: { stats: collaborator_data[:stats] }
      )

      Turbo::StreamsChannel.broadcast_replace_to(
        "user_dashboard_#{collaborator.id}",
        target: "dashboard-collaborated-lists",
        partial: "dashboard/collaborated_lists",
        locals: { lists: collaborator_data[:collaborated_lists] }
      )

      Turbo::StreamsChannel.broadcast_replace_to(
        "user_dashboard_#{collaborator.id}",
        target: "dashboard-recent-activity",
        partial: "dashboard/recent_activity",
        locals: { items: collaborator_data[:recent_items] }
      )
    end
  end

  # Update lists index for all affected users
  def broadcast_lists_index_updates(list = @list)
    # Update lists index for list owner
    owner_lists = list.owner.accessible_lists.includes(:owner, :collaborators, :list_items).order(updated_at: :desc)

    Turbo::StreamsChannel.broadcast_replace_to(
      "user_lists_#{list.owner.id}",
      target: "lists-container",
      partial: "lists/lists_grid",
      locals: { lists: owner_lists }
    )

    # Update lists index for collaborators
    list.collaborators.each do |collaborator|
      collaborator_lists = collaborator.accessible_lists.includes(:owner, :collaborators, :list_items).order(updated_at: :desc)

      Turbo::StreamsChannel.broadcast_replace_to(
        "user_lists_#{collaborator.id}",
        target: "lists-container",
        partial: "lists/lists_grid",
        locals: { lists: collaborator_lists }
      )
    end
  end

  # Broadcast updates to all affected users (both dashboard and lists index)
  def broadcast_all_updates(list = @list)
    broadcast_dashboard_updates(list)
    broadcast_lists_index_updates(list)
  end
end
