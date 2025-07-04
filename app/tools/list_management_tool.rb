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

    service = ListCreationService.new(@user)
    result = service.create_list(title: title, description: description)

    if result.success?
      list = result.data
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
    else
      { error: result.errors.join(", ") }
    end
  end

  def create_planning_list(title, description = nil, planning_context = nil)
    return { error: "Title is required to create a planning list" } if title.blank?

    # Enhanced description generation for planning lists
    if description.blank?
      description = generate_planning_description(title, planning_context)
    end

    service = ListCreationService.new(@user)
    result = service.create_planning_list(
      title: title,
      description: description,
      planning_context: planning_context
    )

    if result.success?
      list = result.data
      items_count = list.list_items.count

      {
        success: true,
        message: "Created planning list '#{list.title}' with #{items_count} initial items",
        list: {
          id: list.id,
          title: list.title,
          description: list.description,
          status: list.status,
          items_count: items_count
        },
        items: list.list_items.map do |item|
          {
            id: item.id,
            title: item.title,
            description: item.description,
            type: item.item_type,
            priority: item.priority
          }
        end
      }
    else
      { error: result.errors.join(", ") }
    end
  end

  def add_item(list_id, title, description = nil)
    return { error: "List ID and title are required to add an item" } if list_id.blank? || title.blank?

    list = find_accessible_list(list_id)
    return { error: "List not found or you don't have permission to edit it" } unless list

    service = ListItemService.new(list, @user)
    result = service.create_item(title: title, description: description)

    if result.success?
      item = result.data
      {
        success: true,
        message: "Added item '#{item.title}' to list '#{list.title}'",
        item: {
          id: item.id,
          title: item.title,
          description: item.description,
          item_type: item.item_type,
          priority: item.priority,
          completed: item.completed,
          position: item.position
        }
      }
    else
      { error: result.errors.join(", ") }
    end
  end

  def complete_item(list_id, item_id)
    return { error: "List ID and item ID are required" } if list_id.blank? || item_id.blank?

    list = find_accessible_list(list_id)
    return { error: "List not found or you don't have permission to edit it" } unless list

    service = ListItemService.new(list, @user)
    result = service.complete_item(item_id)

    if result.success?
      item = result.data
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
    else
      { error: result.errors.join(", ") }
    end
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
          position: item.position,
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
    total = list.list_items_count
    completed = list.list_items.where(completed: true).count
    percentage = total > 0 ? (completed.to_f / total * 100).round : 0

    {
      total: total,
      completed: completed,
      percentage: percentage
    }
  end

  def generate_auto_description(title)
    case title.downcase
    when /vacation|trip|travel/
      "Plan and organize your upcoming travel experience"
    when /project|work/
      "Track progress and manage tasks for this project"
    when /shopping|grocery|store/
      "Keep track of items you need to purchase"
    when /goals|resolution/
      "Set and achieve your personal or professional goals"
    when /meeting|agenda/
      "Organize topics and action items for your meeting"
    when /event|conference|convention/
      "Plan and organize all aspects of this event"
    else
      "Organize and track items for #{title.downcase}"
    end
  end

  def generate_planning_description(title, context)
    case context&.downcase
    when "vacation"
      "Complete travel planning checklist for #{title}"
    when "project"
      "Project management and task tracking for #{title}"
    when "goals"
      "Goal setting and milestone tracking for #{title}"
    when "shopping"
      "Shopping list and purchase planning for #{title}"
    when "event", "conference"
      "Event planning and organization for #{title}"
    else
      generate_auto_description(title)
    end
  end
end
