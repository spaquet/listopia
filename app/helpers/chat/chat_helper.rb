# app/helpers/chat/chat_helper.rb
module Chat::ChatHelper
  # Generate contextual data for the chat component based on current page
  def chat_context
    base_context = {
      page: "#{controller_name}##{action_name}",
      timestamp: Time.current.iso8601
    }

    # NEW: Add context manager data if user is authenticated
    if current_user
      context_manager = ConversationContextManager.new(
        user: current_user,
        chat: current_user.current_chat,
        current_context: base_context
      )

      # Add context summary to help AI understand current state
      context_summary = context_manager.build_context_summary
      base_context.merge!(context_summary)
    end

    # Add specific context based on current controller/action
    case controller_name
    when "lists"
      add_list_context(base_context)
    when "analytics"
      add_analytics_context(base_context)
    when "dashboard"
      add_dashboard_context(base_context)
    when "home"
      add_home_context(base_context)
    else
      add_generic_context(base_context)
    end

    base_context
  end

  # Get AI-ready context instructions
  def ai_context_instructions
    return "" unless current_user

    context_manager = ConversationContextManager.new(
      user: current_user,
      chat: current_user.current_chat,
      current_context: { page: "#{controller_name}##{action_name}" }
    )

    context_manager.get_ai_context_instructions
  end

  # Check if current context has ambiguous references
  def has_contextual_references?
    return false unless current_user

    recent_contexts = current_user.recent_conversation_contexts(10)

    # Check if user has interacted with multiple lists or items recently
    entity_types = recent_contexts.map(&:entity_type).uniq
    entity_types.include?("List") && entity_types.include?("ListItem")
  end

  # Get context suggestions for the current page
  def contextual_suggestions
    suggestions = []

    case controller_name
    when "lists"
      case action_name
      when "show"
        suggestions.concat(list_show_contextual_suggestions)
      when "index"
        suggestions.concat(list_index_contextual_suggestions)
      end
    when "dashboard"
      suggestions.concat(dashboard_contextual_suggestions)
    end

    suggestions
  end

  private

  def add_list_context(context)
    case action_name
    when "show", "edit", "update"
      if defined?(@list) && @list
        list_context = {
          list_id: @list.id,
          list_title: @list.title,
          list_status: @list.status,
          items_count: @list.list_items.count,
          completed_count: @list.list_items.completed.count,
          is_owner: @list.owner == current_user,
          can_collaborate: @list.collaboratable_by?(current_user),
          collaborators_count: @list.collaborators.count
        }

        # NEW: Add recent item interactions
        if current_user
          recent_item_contexts = current_user.conversation_contexts
            .for_entity_type("ListItem")
            .where("entity_data @> ?", { list_id: @list.id }.to_json)
            .recent
            .limit(5)

          list_context[:recent_item_interactions] = recent_item_contexts.map do |ctx|
            {
              action: ctx.action,
              item_title: ctx.entity_data["title"],
              created_at: ctx.created_at
            }
          end
        end

        context.merge!(list_context)
        context[:suggestions] = list_page_suggestions
      end
    when "index"
      if current_user
        index_context = {
          total_lists: current_user.accessible_lists.count,
          my_lists_count: current_user.lists.count,
          collaborated_lists_count: current_user.collaborated_lists.count
        }

        # NEW: Add recently viewed lists
        recent_list_contexts = current_user.conversation_contexts
          .for_entity_type("List")
          .for_action([ "list_viewed", "list_created" ])
          .recent
          .limit(5)

        index_context[:recently_viewed_lists] = recent_list_contexts.map do |ctx|
          {
            list_id: ctx.entity_id,
            list_title: ctx.entity_data["title"],
            action: ctx.action,
            viewed_at: ctx.created_at
          }
        end

        context.merge!(index_context)
        context[:suggestions] = list_index_suggestions
      end
    when "new", "create"
      context.merge!({
        suggestions: list_creation_suggestions
      })
    end
  end

  def add_analytics_context(context)
    if defined?(@list) && @list
      context.merge!({
        list_id: @list.id,
        list_title: @list.title,
        analytics_available: true,
        suggestions: analytics_suggestions
      })
    end
  end

  def add_analytics_context(context)
    if defined?(@list) && @list
      context.merge!({
        list_id: @list.id,
        list_title: @list.title,
        analytics_available: true,
        suggestions: analytics_suggestions
      })
    end
  end

  def add_dashboard_context(context)
    if defined?(@stats) && @stats
      dashboard_context = {
        total_lists: @stats[:total_lists],
        active_lists: @stats[:active_lists],
        completed_lists: @stats[:completed_lists],
        overdue_items: @stats[:overdue_items]
      }

      # NEW: Add recent activity summary
      if current_user
        recent_activity = current_user.conversation_contexts
          .within_timeframe(24)
          .group(:action)
          .count

        dashboard_context[:recent_activity_24h] = recent_activity
      end

      context.merge!(dashboard_context)
      context[:suggestions] = dashboard_suggestions
    end
  end

  def add_home_context(context)
    context.merge!({
      is_landing_page: true,
      suggestions: home_suggestions
    })
  end

  def add_generic_context(context)
    context.merge!({
      suggestions: generic_suggestions
    })
  end

  # Context-specific suggestion methods
  def list_page_suggestions
    suggestions = []

    if defined?(@list) && @list && current_user
      suggestions << "Add items to this list" if @list.collaboratable_by?(current_user)
      suggestions << "Mark items as completed" if @list.list_items.pending.any?
      suggestions << "Set due dates for items" if @list.list_items.where(due_date: nil).any?
      suggestions << "Assign items to collaborators" if @list.collaborators.any?
      suggestions << "Export this list" if @list.readable_by?(current_user)
      suggestions << "Share this list" if @list.owner == current_user
    end

    suggestions
  end

  def list_index_suggestions
    [
      "Create a new list",
      "Search through your lists",
      "Filter lists by status",
      "View collaboration requests"
    ]
  end

  def list_creation_suggestions
    [
      "Create a shopping list",
      "Plan a project",
      "Make a travel checklist",
      "Organize daily tasks"
    ]
  end

  def analytics_suggestions
    [
      "View completion trends",
      "Analyze productivity patterns",
      "Export analytics data",
      "Set productivity goals"
    ]
  end

  def dashboard_suggestions
    [
      "View your most active lists",
      "Check overdue items",
      "Review recent activity",
      "Plan your day"
    ]
  end

  def home_suggestions
    [
      "Get started with Listopia",
      "Create your first list",
      "Learn about collaboration features",
      "Explore planning templates"
    ]
  end

  def generic_suggestions
    [
      "How can I help you today?",
      "What would you like to organize?",
      "Ask me about list management",
      "Get planning assistance"
    ]
  end

  # Context-aware suggestion methods
  def list_show_contextual_suggestions
    suggestions = []
    return suggestions unless defined?(@list) && @list && current_user

    suggestions << "Add items to this list" if @list.collaboratable_by?(current_user)
    suggestions << "Mark items as completed" if @list.list_items.pending.any?
    suggestions << "Set due dates for items" if @list.list_items.where(due_date: nil).any?
    suggestions << "Assign items to collaborators" if @list.collaborators.any?

    # NEW: Context-based suggestions
    if current_user.conversation_contexts.for_action("item_added").within_timeframe(1).any?
      suggestions << "Organize recently added items"
    end

    if @list.list_items.completed.count > @list.list_items.pending.count
      suggestions << "Archive completed items"
    end

    suggestions
  end

  def list_index_contextual_suggestions
    suggestions = []
    return suggestions unless current_user

    suggestions << "Create a new list"
    suggestions << "Search through your lists"

    # NEW: Context-based suggestions
    recent_activity = current_user.conversation_contexts.within_timeframe(24).group(:action).count

    if recent_activity["list_created"].to_i > 0
      suggestions << "Continue working on recently created lists"
    end

    if recent_activity["item_completed"].to_i > 5
      suggestions << "Review completed tasks from today"
    end

    suggestions
  end

  def dashboard_contextual_suggestions
    suggestions = []
    return suggestions unless current_user

    suggestions << "View your most active lists"
    suggestions << "Check overdue items"

    # NEW: Activity-based suggestions
    if current_user.lists.status_active.count > 5
      suggestions << "Archive completed lists to reduce clutter"
    end

    if current_user.has_recent_activity?(6)
      suggestions << "Continue where you left off"
    else
      suggestions << "Start planning your day"
    end

    suggestions
  end
end
