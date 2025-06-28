# app/helpers/chat/chat_helper.rb
module Chat::ChatHelper
  # Generate contextual data for the chat component based on current page
  def chat_context
    context = {
      page: "#{controller_name}##{action_name}",
      timestamp: Time.current.iso8601
    }

    # Add specific context based on current controller/action
    case controller_name
    when "lists"
      add_list_context(context)
    when "analytics"
      add_analytics_context(context)
    when "dashboard"
      add_dashboard_context(context)
    when "home"
      add_home_context(context)
    else
      add_generic_context(context)
    end

    context
  end

  private

  def add_list_context(context)
    case action_name
    when "show", "edit", "update"
      if defined?(@list) && @list
        context.merge!({
          list_id: @list.id,
          list_title: @list.title,
          list_status: @list.status,
          items_count: @list.list_items.count,
          completed_count: @list.list_items.completed.count,
          is_owner: @list.owner == current_user,
          can_collaborate: @list.collaboratable_by?(current_user),
          collaborators_count: @list.collaborators.count,
          suggestions: list_page_suggestions
        })
      end
    when "index"
      if current_user
        context.merge!({
          total_lists: current_user.accessible_lists.count,
          my_lists_count: current_user.lists.count,
          collaborated_lists_count: current_user.collaborated_lists.count,
          suggestions: list_index_suggestions
        })
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

  def add_dashboard_context(context)
    if defined?(@stats) && @stats
      context.merge!({
        total_lists: @stats[:total_lists],
        active_lists: @stats[:active_lists],
        completed_lists: @stats[:completed_lists],
        overdue_items: @stats[:overdue_items],
        suggestions: dashboard_suggestions
      })
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
      suggestions << "Analyze this list's progress"
      suggestions << "Share this list with someone"
      suggestions << "Create a similar list"
    end

    suggestions
  end

  def list_index_suggestions
    [
      "Create a new list",
      "Show me my incomplete tasks",
      "What lists need attention?",
      "Create a grocery list",
      "Make a project plan",
      "Show overdue items"
    ]
  end

  def list_creation_suggestions
    [
      "Create a grocery list with common items",
      "Make a project timeline",
      "Build a travel checklist",
      "Start a reading list",
      "Plan a weekly routine"
    ]
  end

  def analytics_suggestions
    [
      "Explain these analytics",
      "What insights can you find?",
      "How can I improve productivity?",
      "Show completion trends",
      "Compare with other lists"
    ]
  end

  def dashboard_suggestions
    [
      "What should I focus on today?",
      "Show me overdue items",
      "Create a daily planning list",
      "Review my progress this week",
      "What lists need attention?"
    ]
  end

  def home_suggestions
    [
      "Tell me about Listopia features",
      "How does collaboration work?",
      "Create my first list",
      "What can I do with lists?"
    ]
  end

  def generic_suggestions
    [
      "Create a new list",
      "Show my lists",
      "Help me get organized",
      "What can you help me with?"
    ]
  end
end
