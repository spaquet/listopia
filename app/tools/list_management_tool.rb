# app/tools/list_management_tool.rb
class ListManagementTool < RubyLLM::Tool
  description "Manages lists and list items in Listopia. Use this tool for ANY planning, organization, or task management needs."

  param :action, desc: "The action to perform",
        enum: [ "create_list", "add_item", "complete_item", "get_lists", "get_list_items", "create_planning_list" ]
  param :title, desc: "Title for new lists or items", required: false
  param :description, desc: "Description for new lists or items", required: false
  param :list_id, desc: "The ID or reference to the list", required: false
  param :item_id, desc: "The ID of the item", required: false
  param :planning_context, desc: "Context for planning", required: false

  def initialize(user, context = {})
    @user = user
    @context = context
  end

  def execute(action:, **params)
    case action
    when "create_list"
      create_list(params[:title], params[:description])
    when "create_planning_list"
      create_planning_list(params[:title], params[:description], params[:planning_context])
    when "add_item"
      add_item(params[:list_id], params[:title], params[:description])
    when "get_lists"
      get_lists
    when "get_list_items"
      get_list_items(params[:list_id])
    when "complete_item"
      complete_item(params[:item_id])
    else
      { error: "Unknown action: #{action}" }
    end
  rescue => e
    Rails.logger.error "ListManagementTool error: #{e.message}"
    { error: e.message }
  end

  private

  def create_list(title, description = nil)
    list = @user.lists.create!(
      title: title,
      description: description,
      status: "active"
    )

    broadcast_list_update(list)

    {
      success: true,
      message: "Created list '#{title}'",
      list: serialize_list(list)
    }
  end

  def create_planning_list(title, description, context)
    list = create_list(title, description)

    # Add contextual items based on planning context
    if context&.downcase&.include?("roadshow")
      cities = extract_cities_from_context(description || title)
      cities.each do |city|
        add_item(list[:list][:id], "#{city} stop", "Plan and execute roadshow stop in #{city}")
      end
    end

    list
  end

  def add_item(list_id, title, description = nil)
    list = find_list(list_id)
    return { error: "List not found" } unless list

    item = list.list_items.create!(
      title: title,
      description: description,
      position: list.list_items.count
    )

    broadcast_item_update(item)

    {
      success: true,
      message: "Added item '#{title}' to list",
      item: serialize_item(item)
    }
  end

  def extract_cities_from_context(text)
    # Simple city extraction - could be enhanced
    cities = %w[San\ Francisco New\ York Austin Denver Seattle Portland Boston Los\ Angeles]
    cities.select { |city| text.match?(/#{city}/i) }
  end

  def find_list(list_id)
    if list_id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
      @user.lists.find_by(id: list_id)
    else
      @user.lists.find_by(title: list_id)
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

  def serialize_item(item)
    {
      id: item.id,
      title: item.title,
      description: item.description,
      completed: item.completed,
      position: item.position
    }
  end

  def broadcast_list_update(list)
    # Keep existing broadcast logic
    list.user.broadcast_prepend_to(
      "user_lists_#{list.user.id}",
      target: "lists-grid",
      partial: "lists/list_card",
      locals: { list: list }
    )
  end

  def broadcast_item_update(item)
    # Keep existing broadcast logic for items
    item.list.broadcast_append_to(
      "list_items_#{item.list.id}",
      target: "list-items",
      partial: "list_items/item",
      locals: { item: item }
    )
  end
end
