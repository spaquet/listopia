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

    Rails.logger.info "Creating planning list: #{title} with context: #{planning_context}"

    service = ListCreationService.new(@user)
    result = service.create_planning_list(
      title: title,
      description: description,
      planning_context: planning_context
    )

    # Check if result is nil (service failed to return result)
    if result.nil?
      Rails.logger.error "ListCreationService returned nil result"
      return { error: "Failed to create planning list - service returned no result" }
    end

    if result.success?
      list = result.data
      # Reload to ensure we have the latest count
      list.reload
      items_count = list.list_items.count

      Rails.logger.info "Successfully created planning list #{list.id} with #{items_count} items"

      # Prepare detailed response with all created items
      response = {
        success: true,
        message: "Created planning list '#{list.title}' with #{items_count} initial items",
        list: {
          id: list.id,
          title: list.title,
          description: list.description,
          status: list.status,
          items_count: items_count,
          created_at: list.created_at,
          updated_at: list.updated_at
        }
      }

      # Include detailed items information if items were created
      if items_count > 0
        response[:items] = list.list_items.order(:position).map do |item|
          {
            id: item.id,
            title: item.title,
            description: item.description,
            type: item.item_type,
            priority: item.priority,
            position: item.position,
            completed: item.completed
          }
        end
      end

      response
    else
      Rails.logger.error "Failed to create planning list: #{result.errors.join(', ')}"
      { error: result.errors.join(", ") }
    end
  rescue => e
    Rails.logger.error "Exception in create_planning_list: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    { error: "Failed to create planning list: #{e.message}" }
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
        message: "Marked '#{item.title}' as completed",
        item: {
          id: item.id,
          title: item.title,
          completed: item.completed,
          completed_at: item.completed_at
        }
      }
    else
      { error: result.errors.join(", ") }
    end
  end

  def get_lists
    lists = @user.accessible_lists.order(updated_at: :desc).limit(20)

    {
      success: true,
      lists: lists.map do |list|
        {
          id: list.id,
          title: list.title,
          description: list.description,
          status: list.status,
          items_count: list.list_items.count,
          completed_items: list.list_items.where(completed: true).count,
          is_owner: list.owner == @user,
          updated_at: list.updated_at
        }
      end
    }
  end

  def get_list_items(list_id)
    return { error: "List ID is required" } if list_id.blank?

    list = find_accessible_list(list_id)
    return { error: "List not found or you don't have permission to view it" } unless list

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
          due_date: item.due_date,
          position: item.position,
          created_at: item.created_at,
          updated_at: item.updated_at
        }
      end
    }
  end

  # Helper methods

  def find_accessible_list(list_id)
    @user.accessible_lists.find_by(id: list_id)
  end

  def generate_auto_description(title)
    context_hints = {
      /grocery|shopping|store/i => "Keep track of items to buy during your shopping trip",
      /vacation|travel|trip/i => "Plan and organize your travel experience",
      /project|work|task/i => "Manage project tasks and deliverables",
      /goals?|resolution/i => "Track progress toward your personal objectives",
      /meeting|agenda/i => "Organize discussion points and action items",
      /packing|move|moving/i => "Organize items for packing or moving",
      /wedding|party|event/i => "Plan and coordinate your special event",
      /learning|study|course/i => "Track your educational progress and materials",
      /fitness|workout|exercise/i => "Monitor your health and fitness activities",
      /budget|finance|money/i => "Manage your financial planning and expenses"
    }

    description = context_hints.find { |pattern, _| title.match?(pattern) }&.last
    description || "A organized list to help you stay on track with your goals"
  end

  def generate_planning_description(title, context)
    case context&.downcase
    when "conference"
      "Comprehensive planning checklist for organizing a successful conference event"
    when "vacation", "travel"
      "Complete travel planning guide to ensure a smooth and enjoyable trip"
    when "project"
      "Structured project management approach to deliver successful outcomes"
    when "goals"
      "Strategic goal-setting framework to achieve your personal objectives"
    when "shopping"
      "Organized shopping approach to stay on budget and get everything you need"
    when "wedding"
      "Complete wedding planning timeline to create your perfect day"
    when "moving", "relocation"
      "Comprehensive moving checklist to ensure a smooth transition"
    else
      generate_auto_description(title)
    end
  end
end
