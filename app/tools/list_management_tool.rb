# app/tools/list_management_tool.rb
class ListManagementTool < RubyLLM::Tool
  description "Manages lists and list items in Listopia. Use this tool for ANY planning, organization, or task management needs."

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
    desc: "Description for new lists or items",
    required: false

  param :item_id,
    type: :string,
    desc: "The ID of the item (required for item-specific actions)",
    required: false

  param :planning_context,
    type: :string,
    desc: "Context for planning (e.g., 'event planning', 'travel', 'project management') - helps generate appropriate items",
    required: false

  def initialize(user, context = {})
    @user = user
    @context = context
  end

  def execute(action:, list_id: nil, title: nil, description: nil, item_id: nil, planning_context: nil)
    Rails.logger.info "ListManagementTool executing: #{action} with title: #{title}"

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
      {
        success: false,
        error: "Unknown action: #{action}. Available actions: create_list, create_planning_list, add_item, complete_item, get_lists, get_list_items"
      }
    end
  rescue => e
    Rails.logger.error "ListManagementTool error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    {
      success: false,
      error: "Failed to #{action}: #{e.message}"
    }
  end

  private

  def create_planning_list(title, description = nil, planning_context = nil)
    return { success: false, error: "Title is required to create a planning list" } if title.blank?

    # Auto-generate description if not provided
    if description.blank?
      description = generate_smart_description(title, planning_context)
    end

    # Map the planning context intelligently
    mapped_context = PlanningContextMapper.map_context(planning_context || "", title)

    Rails.logger.info "Creating planning list: #{title} with context: #{mapped_context}"

    service = ListCreationService.new(@user)
    result = service.create_planning_list(
      title: title,
      description: description,
      planning_context: mapped_context
    )

    if result.nil?
      Rails.logger.error "ListCreationService returned nil result"
      return {
        success: false,
        error: "Failed to create planning list - service returned no result"
      }
    end

    if result.success?
      list = result.data
      list.reload
      items_count = list.list_items.count

      Rails.logger.info "Successfully created planning list #{list.id} with #{items_count} items"

      {
        success: true,
        message: "Created planning list '#{list.title}' with #{items_count} initial items",
        list: serialize_list_with_items(list)
      }
    else
      Rails.logger.error "Failed to create planning list: #{result.errors.join(', ')}"
      {
        success: false,
        error: result.errors.join(", ")
      }
    end
  rescue => e
    Rails.logger.error "Exception in create_planning_list: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    {
      success: false,
      error: "Failed to create planning list: #{e.message}"
    }
  end

  def create_list(title, description = nil)
    return { success: false, error: "Title is required to create a list" } if title.blank?

    if description.blank?
      description = generate_smart_description(title)
    end

    service = ListCreationService.new(@user)
    result = service.create_list(title: title, description: description)

    if result.success?
      list = result.data
      {
        success: true,
        message: "Created list '#{list.title}'",
        list: serialize_list(list)
      }
    else
      {
        success: false,
        error: result.errors.join(", ")
      }
    end
  end

  def add_item(list_id, title, description = nil)
    return { success: false, error: "List ID and title are required to add an item" } if list_id.blank? || title.blank?

    list = find_accessible_list(list_id)
    return { success: false, error: "List not found or you don't have permission to modify it" } unless list

    items_service = ListItemService.new(list, @user)
    result = items_service.create_item(
      title: title,
      description: description || "Added via AI assistant"
    )

    if result.success?
      item = result.data
      {
        success: true,
        message: "Added item '#{item.title}' to list '#{list.title}'",
        item: serialize_item(item)
      }
    else
      {
        success: false,
        error: result.errors.join(", ")
      }
    end
  end

  def complete_item(list_id, item_id)
    return { success: false, error: "List ID and item ID are required" } if list_id.blank? || item_id.blank?

    list = find_accessible_list(list_id)
    return { success: false, error: "List not found or you don't have permission to modify it" } unless list

    item = list.list_items.find_by(id: item_id)
    return { success: false, error: "Item not found in this list" } unless item

    items_service = ListItemService.new(list, @user)
    result = items_service.complete_item(item.id)

    if result.success?
      {
        success: true,
        message: "Marked item '#{item.title}' as completed",
        item: serialize_item(item.reload)
      }
    else
      {
        success: false,
        error: result.errors.join(", ")
      }
    end
  end

  def get_lists
    lists = @user.accessible_lists.recent.limit(20)

    {
      success: true,
      lists: lists.map { |list| serialize_list(list) }
    }
  end

  def get_list_items(list_id)
    return { success: false, error: "List ID is required" } if list_id.blank?

    list = find_accessible_list(list_id)
    return { success: false, error: "List not found or you don't have permission to view it" } unless list

    items = list.list_items.order(:position, :created_at)

    {
      success: true,
      list: serialize_list(list),
      items: items.map { |item| serialize_item(item) }
    }
  end

  # Helper methods
  def find_accessible_list(list_id)
    @user.accessible_lists.find_by(id: list_id)
  end

  def serialize_list(list)
    {
      id: list.id,
      title: list.title,
      description: list.description,
      status: list.status,
      items_count: list.list_items.count,
      completed_count: list.list_items.where(completed: true).count,
      created_at: list.created_at,
      updated_at: list.updated_at
    }
  end

  def serialize_list_with_items(list)
    base_list = serialize_list(list)

    if list.list_items.any?
      base_list[:items] = list.list_items.order(:position).map { |item| serialize_item(item) }
    end

    base_list
  end

  def serialize_item(item)
    {
      id: item.id,
      title: item.title,
      description: item.description,
      type: item.item_type,
      priority: item.priority,
      position: item.position,
      completed: item.completed,
      due_date: item.due_date,
      created_at: item.created_at,
      updated_at: item.updated_at
    }
  end

  def generate_smart_description(title, context = nil)
    if context.present?
      "Organized planning for #{title.downcase} with focus on #{context}"
    else
      "An organized approach to #{title.downcase}"
    end
  end

  def serialize_list(list)
    {
      id: list.id,
      title: list.title,
      description: list.description,
      status: list.status,
      items_count: list.list_items.count,
      completed_count: list.list_items.where(completed: true).count,
      created_at: list.created_at,
      updated_at: list.updated_at
    }
  end

  def serialize_list_with_items(list)
    base_list = serialize_list(list)

    if list.list_items.any?
      base_list[:items] = list.list_items.order(:position).map { |item| serialize_item(item) }
    end

    base_list
  end

  def serialize_item(item)
    {
      id: item.id,
      title: item.title,
      description: item.description,
      type: item.item_type,
      priority: item.priority,
      position: item.position,
      completed: item.completed,
      due_date: item.due_date,
      created_at: item.created_at,
      updated_at: item.updated_at
    }
  end
end
