# app/tools/list_management_tool.rb
class ListManagementTool < RubyLLM::Tool
  description "Manages lists and list items in Listopia. Use this tool for ANY planning, organization, or task management needs - including vacation planning, project management, goal setting, etc."

  param :action,
    type: :string,
    desc: "The action to perform: 'create_list', 'add_item', 'complete_item', 'get_lists', 'get_list_items', 'create_planning_list'"

  param :list_id,
    type: :string,
    desc: "The ID of the list (required for list-specific actions)",
    required: false

  param :title,
    type: :string,
    desc: "Title for new lists or items",
    required: false

  param :description,
    type: :string,
    desc: "Description for new lists or items (recommended for better organization)",
    required: false

  param :item_id,
    type: :string,
    desc: "The ID of the item (required for item-specific actions)",
    required: false

  param :planning_context,
    type: :string,
    desc: "Context for planning (e.g., 'vacation', 'project', 'goals', 'shopping') - helps generate appropriate items",
    required: false

  def initialize(user, context = {})
    @user = user
    @context = context
  end

  def execute(action:, list_id: nil, title: nil, description: nil, item_id: nil, planning_context: nil)
    case action
    when "create_list"
      create_list(title, description)
    when "create_planning_list"
      create_planning_list(title, description, planning_context)
    when "add_item"
      add_item(list_id, title, description)
    when "complete_item"
      complete_item(list_id, item_id)
    when "get_lists"
      get_lists
    when "get_list_items"
      get_list_items(list_id)
    else
      { error: "Unknown action: #{action}. Available actions: create_list, create_planning_list, add_item, complete_item, get_lists, get_list_items" }
    end
  rescue => e
    Rails.logger.error "ListManagementTool error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    { error: "Failed to #{action}: #{e.message}" }
  end

  private

  def create_list(title, description = nil)
    return { error: "Title is required to create a list" } if title.blank?

    # Auto-generate description if not provided
    if description.blank?
      description = generate_auto_description(title)
    end

    list = @user.lists.create!(
      title: title,
      description: description,
      status: :active
    )

    {
      success: true,
      message: "Created list '#{list.title}' with description",
      list: {
        id: list.id,
        title: list.title,
        description: list.description,
        status: list.status
      }
    }
  end

  def create_planning_list(title, description = nil, planning_context = nil)
    return { error: "Title is required to create a planning list" } if title.blank?

    # Enhanced description generation for planning lists
    if description.blank?
      description = generate_planning_description(title, planning_context)
    end

    list = @user.lists.create!(
      title: title,
      description: description,
      status: :active
    )

    # Auto-generate planning items based on context
    added_items = []
    if planning_context.present?
      suggested_items = generate_planning_items(planning_context, title)
      suggested_items.each do |item_data|
        created_item = list.list_items.create!(
          title: item_data[:title],
          description: item_data[:description],
          item_type: item_data[:type] || "task",
          priority: item_data[:priority] || "medium"
        )
        added_items << created_item
      end
    end

    {
      success: true,
      message: "Created planning list '#{list.title}' with #{added_items.count} initial items",
      list: {
        id: list.id,
        title: list.title,
        description: list.description,
        status: list.status,
        items_count: added_items.count
      },
      items: added_items.map do |item|
        {
          id: item.id,
          title: item.title,
          description: item.description,
          type: item.item_type,
          priority: item.priority
        }
      end
    }
  end

  def add_item(list_id, title, description = nil)
    return { error: "List ID and title are required to add an item" } if list_id.blank? || title.blank?

    list = find_accessible_list(list_id)
    return { error: "List not found or you don't have permission to edit it" } unless list

    unless can_edit_list?(list)
      return { error: "You don't have permission to add items to this list" }
    end

    # Auto-generate description if not provided
    if description.blank?
      description = generate_item_description(title, list)
    end

    item = list.list_items.create!(
      title: title,
      description: description,
      item_type: determine_item_type(title, list.title),
      priority: :medium
    )

    {
      success: true,
      message: "Added item '#{item.title}' to list '#{list.title}'",
      item: {
        id: item.id,
        title: item.title,
        description: item.description,
        item_type: item.item_type,
        priority: item.priority,
        completed: item.completed
      }
    }
  end

  def complete_item(list_id, item_id)
    return { error: "List ID and item ID are required" } if list_id.blank? || item_id.blank?

    list = find_accessible_list(list_id)
    return { error: "List not found or you don't have permission to edit it" } unless list

    unless can_edit_list?(list)
      return { error: "You don't have permission to modify items in this list" }
    end

    item = list.list_items.find_by(id: item_id)
    return { error: "Item not found" } unless item

    item.update!(completed: true, completed_at: Time.current)

    {
      success: true,
      message: "Completed item '#{item.title}'",
      item: {
        id: item.id,
        title: item.title,
        completed: true,
        completed_at: item.completed_at
      }
    }
  end

  def get_lists
    lists = @user.accessible_lists.includes(:list_items)

    {
      success: true,
      lists: lists.map do |list|
        stats = calculate_list_stats(list)
        {
          id: list.id,
          title: list.title,
          description: list.description,
          status: list.status,
          items_count: stats[:total],
          completed_count: stats[:completed],
          completion_percentage: stats[:percentage],
          is_owner: list.user_id == @user.id,
          can_edit: can_edit_list?(list)
        }
      end
    }
  end

  def get_list_items(list_id)
    return { error: "List ID is required" } if list_id.blank?

    list = find_accessible_list(list_id)
    return { error: "List not found or you don't have access" } unless list

    items = list.list_items.order(:position, :created_at)

    {
      success: true,
      list: {
        id: list.id,
        title: list.title,
        description: list.description
      },
      items: items.map do |item|
        {
          id: item.id,
          title: item.title,
          description: item.description,
          item_type: item.item_type,
          priority: item.priority,
          completed: item.completed,
          completed_at: item.completed_at,
          due_date: item.due_date,
          assigned_user: item.assigned_user&.email
        }
      end
    }
  end

  # Helper methods

  def find_accessible_list(list_id)
    @user.accessible_lists.find_by(id: list_id)
  end

  def can_edit_list?(list)
    return true if list.user_id == @user.id

    collaboration = list.list_collaborations.find_by(user: @user)
    collaboration&.permission_collaborate?
  end

  def calculate_list_stats(list)
    total = list.list_items.count
    completed = list.list_items.where(completed: true).count
    percentage = total > 0 ? (completed.to_f / total * 100).round : 0

    {
      total: total,
      completed: completed,
      pending: total - completed,
      percentage: percentage
    }
  end

  def generate_auto_description(title)
    case title.downcase
    when /grocery|shopping|store/
      "Shopping list for grocery items and essentials"
    when /vacation|trip|travel/
      "Travel planning and itinerary organization"
    when /project|sprint|development/
      "Project planning and task management"
    when /goal|resolution|objective/
      "Goal tracking and milestone management"
    when /meeting|agenda/
      "Meeting agenda and action items"
    when /packing|pack/
      "Packing checklist and travel preparation"
    else
      "Organized list for better task management"
    end
  end

  def generate_planning_description(title, context)
    case context&.downcase
    when "vacation", "travel", "trip"
      "Complete travel planning including flights, accommodations, activities, and logistics"
    when "project", "sprint", "development"
      "Project breakdown with tasks, milestones, and deliverables"
    when "goals", "objectives", "resolutions"
      "Goal setting with actionable steps and progress tracking"
    when "shopping", "grocery"
      "Shopping list with items organized by category or store section"
    when "meeting", "agenda"
      "Meeting preparation with agenda items and follow-up actions"
    when "event", "party", "celebration"
      "Event planning with tasks, timeline, and vendor coordination"
    else
      generate_auto_description(title)
    end
  end

  def generate_planning_items(context, title)
    case context.downcase
    when "vacation", "travel", "trip"
      [
        { title: "Book flights", description: "Research and book round-trip flights", type: "task", priority: "high" },
        { title: "Reserve accommodations", description: "Book hotels or vacation rentals", type: "task", priority: "high" },
        { title: "Plan itinerary", description: "Research activities and create daily schedule", type: "task", priority: "medium" },
        { title: "Check passport/documents", description: "Ensure all travel documents are valid", type: "task", priority: "high" },
        { title: "Purchase travel insurance", description: "Get coverage for trip protection", type: "task", priority: "medium" },
        { title: "Create packing list", description: "Plan what to pack based on weather and activities", type: "task", priority: "low" }
      ]
    when "project", "sprint"
      [
        { title: "Define project scope", description: "Clearly outline project boundaries and objectives", type: "task", priority: "high" },
        { title: "Create project timeline", description: "Set milestones and deadlines", type: "task", priority: "high" },
        { title: "Assign team roles", description: "Delegate responsibilities to team members", type: "task", priority: "medium" },
        { title: "Set up project tools", description: "Configure necessary software and platforms", type: "task", priority: "medium" },
        { title: "Schedule regular check-ins", description: "Plan team meetings and progress reviews", type: "task", priority: "low" }
      ]
    when "goals", "objectives"
      [
        { title: "Define SMART goals", description: "Make goals Specific, Measurable, Achievable, Relevant, Time-bound", type: "task", priority: "high" },
        { title: "Break down into steps", description: "Create actionable sub-tasks", type: "task", priority: "high" },
        { title: "Set milestones", description: "Define checkpoints to track progress", type: "task", priority: "medium" },
        { title: "Create accountability system", description: "Set up tracking and review process", type: "task", priority: "medium" },
        { title: "Plan reward system", description: "Define rewards for achieving milestones", type: "task", priority: "low" }
      ]
    else
      []
    end
  end

  def determine_item_type(title, context = nil)
    title_lower = title.downcase
    context_lower = context&.downcase || ""

    # Default to 'task' for compatibility
    "task"
  end

  def generate_item_description(title, list)
    list_context = list.title.downcase

    case list_context
    when /grocery|shopping/
      "#{title} - Add to shopping cart"
    when /vacation|travel/
      "#{title} - Travel planning task"
    when /project/
      "#{title} - Project deliverable"
    else
      nil
    end
  end
end
