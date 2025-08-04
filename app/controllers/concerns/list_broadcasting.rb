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
      locals: { lists: owner_data[:my_lists], current_user: list.owner }
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
        locals: { lists: collaborator_data[:collaborated_lists], current_user: collaborator }
      )

      Turbo::StreamsChannel.broadcast_replace_to(
        "user_dashboard_#{collaborator.id}",
        target: "dashboard-recent-activity",
        partial: "dashboard/recent_activity",
        locals: { items: collaborator_data[:recent_items] }
      )
    end
  end

  # NEW: Broadcast specific list card creation (for create actions)
  def broadcast_list_creation(list = @list)
    affected_users = [list.owner]
    affected_users.concat(list.collaborators) if list.collaborators.any?

    affected_users.uniq.each do |user|
      # Prepend new list card to lists grid (if user is on lists index)
      Turbo::StreamsChannel.broadcast_prepend_to(
        "user_lists_#{user.id}",
        target: "lists-grid",
        partial: "lists/list_card",
        locals: { list: list, current_user: user }
      )

      # Remove empty state if this might be the first list
      Turbo::StreamsChannel.broadcast_remove_to(
        "user_lists_#{user.id}",
        target: "empty-state"
      )
    end
  end

  # NEW: Broadcast specific list card updates (for update actions)
  def broadcast_list_update(list = @list)
    affected_users = [list.owner]
    affected_users.concat(list.collaborators) if list.collaborators.any?

    affected_users.uniq.each do |user|
      # Update specific list card in turbo frame
      Turbo::StreamsChannel.broadcast_replace_to(
        "user_lists_#{user.id}",
        target: "list_card_#{list.id}",
        partial: "lists/list_card",
        locals: { list: list, current_user: user }
      )
    end
  end

  # NEW: Broadcast specific list card removal (for destroy actions)
  def broadcast_list_deletion(list = @list, user_lists_count = nil)
    affected_users = [list.owner]
    affected_users.concat(list.collaborators) if list.collaborators.any?

    affected_users.uniq.each do |user|
      # Remove specific list card turbo frame
      Turbo::StreamsChannel.broadcast_remove_to(
        "user_lists_#{user.id}",
        target: "list_card_#{list.id}"
      )

      # Show empty state if no lists remaining (if count provided)
      if user_lists_count && user_lists_count == 0
        Turbo::StreamsChannel.broadcast_replace_to(
          "user_lists_#{user.id}",
          target: "lists-container",
          partial: "lists/empty_state"
        )
      end
    end
  end

  # DEPRECATED: Keep for backward compatibility but prefer specific methods above
  def broadcast_lists_index_updates(list = @list)
    # For backward compatibility, just call the update method
    broadcast_list_update(list)
  end

  # Updated to use specific broadcasting methods
  def broadcast_all_updates(list = @list, action: :update)
    broadcast_dashboard_updates(list)

    case action
    when :create
      broadcast_list_creation(list)
    when :update
      broadcast_list_update(list)
    when :destroy
      user_count = list.owner.accessible_lists.count - 1 # Subtract the one being deleted
      broadcast_list_deletion(list, user_count)
    else
      broadcast_list_update(list) # Default fallback
    end
  end
end
