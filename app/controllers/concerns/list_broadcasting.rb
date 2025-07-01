# app/controllers/concerns/list_broadcasting.rb
module ListBroadcasting
  extend ActiveSupport::Concern

  private

  # Update dashboard for all affected users
  def broadcast_dashboard_updates(list = @list)
    # Update dashboard for list owner
    owner_data = view_context.dashboard_data_for_user(list.owner)

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
      collaborator_data = view_context.dashboard_data_for_user(collaborator)

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
