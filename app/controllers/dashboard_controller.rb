# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @stats = DashboardStatsService.new(current_user, current_organization).call

    # Build context for adaptive dashboard
    dashboard_context = {
      selected_list_id: params[:focus_list_id],
      in_chat: params[:chat_mode] == "true",
      chat_available: true,
      user_id: current_user.id,
      organization_id: current_organization&.id
    }

    # Get adaptive dashboard data
    @adaptive_dashboard = DashboardAdaptiveService.new(current_user, dashboard_context).call

    # For backward compatibility with turbo streams
    @recent_items = generate_recent_items
  end

  # Kanban board view of all lists grouped by status
  def kanban
    # Get lists accessible by user with status grouping
    if current_organization
      lists = policy_scope(List).where(organization_id: current_organization.id)
    else
      lists = policy_scope(List).where(organization_id: nil)
    end

    # Group lists by status for kanban view
    @lists_by_status = lists.includes(:owner, :collaborators)
                            .order(updated_at: :desc)
                            .group_by(&:status)

    # Ensure all statuses have a group (even if empty)
    List.statuses.each_key do |status|
      @lists_by_status[status] ||= []
    end
  end

  # Kanban board view of all items from active lists
  def items_kanban
    # Get active lists accessible by user
    if current_organization
      lists = policy_scope(List).where(organization_id: current_organization.id, status: :active)
    else
      lists = policy_scope(List).where(organization_id: nil, status: :active)
    end

    # Load all items from active lists with their associations
    @items = ListItem.where(list: lists)
                     .includes(:list, :board_column, :assigned_user)
                     .reorder(:position, :created_at)

    # Group items by board column (using a pseudo-column structure)
    # We create virtual columns for display purposes
    @column_names = [ "To Do", "In Progress", "Done" ]
    @items_by_column = {}

    @column_names.each do |column_name|
      @items_by_column[column_name] = @items.select do |item|
        case column_name
        when "To Do"
          item.status_pending?
        when "In Progress"
          item.status_in_progress?
        when "Done"
          item.status_completed?
        end
      end
    end
  end

  # New action for switching focus in the sidebar
  def focus_list
    list_id = params[:list_id]
    mode = params[:mode]&.to_sym

    # Build context
    context = {
      selected_list_id: list_id,
      in_chat: false,
      chat_available: true,
      user_id: current_user.id,
      organization_id: current_organization&.id,
      forced_mode: mode  # Force a specific mode for testing
    }

    @adaptive_dashboard = DashboardAdaptiveService.new(current_user, context).call

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "dashboard-adaptive-sidebar",
          partial: "dashboard/adaptive_sidebar",
          locals: { adaptive_dashboard: @adaptive_dashboard, current_user: current_user }
        )
      end
    end
  end

  # Execute an action from the action panel
  def execute_action
    action_type = params[:action_type]
    list_id = params[:list_id]
    item_id = params[:item_id]

    case action_type
    when "create_list"
      redirect_to new_list_path
    when "add_item"
      list = current_user.accessible_lists.find_by(id: list_id)
      redirect_to new_list_item_path(list) if list
    when "mark_complete"
      item = ListItem.find_by(id: item_id)
      if item&.update(status: :completed, status_changed_at: Time.current)
        respond_to do |format|
          format.turbo_stream do
            # Refresh the adaptive sidebar
            context = {
              selected_list_id: list_id,
              in_chat: false,
              chat_available: true,
              user_id: current_user.id
            }
            @adaptive_dashboard = DashboardAdaptiveService.new(current_user, context).call
            render turbo_stream: [
              turbo_stream.replace(
                "dashboard-adaptive-sidebar",
                partial: "dashboard/adaptive_sidebar",
                locals: { adaptive_dashboard: @adaptive_dashboard, current_user: current_user }
              ),
              turbo_stream.update("flash-messages") do
                render_to_string(partial: "shared/flash_success", locals: { message: "Item marked as complete!" })
              end
            ]
          end
        end
      end
    when "view_list"
      list = current_user.accessible_lists.find_by(id: list_id)
      redirect_to list if list
    when "invite_collaborator"
      list = current_user.accessible_lists.find_by(id: list_id)
      redirect_to list_collaborations_path(list) if list
    when "chat_action"
      # This would be handled by the chat component
      render json: { redirect: false, action: "focus_chat" }
    end
  end

  private

  # Generate recent items for backward compatibility
  def generate_recent_items
    lists = if current_organization
      current_organization.lists.where(user_id: current_user.id)
    else
      current_user.lists.where(organization_id: nil)
    end

    ListItem.joins(:list)
            .where(list: lists)
            .includes(:list)
            .order(updated_at: :desc)
            .limit(20)
  end
end
