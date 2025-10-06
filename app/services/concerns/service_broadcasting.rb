# app/services/concerns/service_broadcasting.rb
module ServiceBroadcasting
  extend ActiveSupport::Concern

  private

  # Context-aware broadcasting that works from both controllers and services
  # Use skip_broadcasts: true to prevent broadcasting during intermediate steps
  def broadcast_all_updates(list, skip_broadcasts: false, action: :update)
    return if skip_broadcasts

    broadcast_dashboard_updates(list)
    broadcast_lists_index_updates(list, action: action)
  end

  # Update dashboard for all affected users (service-safe version)
  def broadcast_dashboard_updates(list)
    # Get all affected users efficiently
    affected_users = [ list.owner ]

    # Only load collaborators if list has any (avoid N+1)
    if list.list_collaborations_count > 0
      affected_users.concat(list.collaborators.to_a)
    end

    affected_users.uniq.each do |user|
      begin
        user_data = dashboard_data_for_user(user)

        # Broadcast stats update
        Turbo::StreamsChannel.broadcast_replace_to(
          "user_dashboard_#{user.id}",
          target: "dashboard-stats",
          partial: "dashboard/stats_overview",
          locals: { stats: user_data[:stats] }
        )

        # Broadcast appropriate lists section based on relationship to list

        # Update recent activity for all affected users
        Turbo::StreamsChannel.broadcast_replace_to(
          "user_dashboard_#{user.id}",
          target: "dashboard-recent-activity",
          partial: "dashboard/recent_activity",
          locals: { items: user_data[:recent_items] }
        )
      rescue => e
        # Log error but don't fail the entire operation
        Rails.logger.error "Failed to broadcast dashboard update for user #{user.id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
    end
  end

  # Updated lists index broadcasting with Turbo Frame support
  def broadcast_lists_index_updates(list, action: :update)
    affected_users = [ list.owner ]

    if list.list_collaborations_count > 0
      affected_users.concat(list.collaborators.to_a)
    end

    affected_users.uniq.each do |user|
      begin
        case action
        when :create
          # Prepend new list card to lists grid
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

        when :destroy
          # Remove specific list card
          Turbo::StreamsChannel.broadcast_remove_to(
            "user_lists_#{user.id}",
            target: "list_card_#{list.id}"
          )

          # Show empty state if no lists remaining
          user_lists_count = user.accessible_lists.count - 1 # Subtract the one being deleted
          if user_lists_count == 0
            Turbo::StreamsChannel.broadcast_replace_to(
              "user_lists_#{user.id}",
              target: "lists-container",
              partial: "lists/empty_state"
            )
          end

        else # :update or any other action
          # Update specific list card
          Turbo::StreamsChannel.broadcast_replace_to(
            "user_lists_#{user.id}",
            target: "list_card_#{list.id}",
            partial: "lists/list_card",
            locals: { list: list, current_user: user }
          )
        end

      rescue => e
        Rails.logger.error "Failed to broadcast lists index update for user #{user.id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
    end
  end

  # Service-safe method to get dashboard data without view_context
  # Optimized to avoid N+1 queries
  def dashboard_data_for_user(user)
    # Get accessible list IDs efficiently
    accessible_list_ids = user.accessible_lists.pluck(:id)

    {
      stats: calculate_dashboard_stats_for_user(user, accessible_list_ids),
      recent_items: ListItem.joins(:list)
                           .where(list_id: accessible_list_ids)
                           .includes(:list)
                           .order(created_at: :desc)
                           .limit(10)
    }
  end

  # Calculate statistics efficiently without N+1 queries
  def calculate_dashboard_stats_for_user(user, accessible_list_ids = nil)
    # Use the service object for consistency
    DashboardStatsService.new(user).call
  end
end
