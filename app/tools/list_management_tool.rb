# app/tools/list_management_tool.rb
class ListManagementTool < RubyLLM::Tool
  description "Manages lists and list items in Listopia. Use this tool for ANY planning, organization, or task management needs. You can create main lists, sub-lists, and organize complex projects intelligently."

  # RubyLLM 1.8+ compatible parameter definitions (no enum keyword)
  param :action, desc: "Action to perform: create_list, create_sub_lists, add_item, get_lists, get_list_items, complete_item"
  param :title, desc: "Title for new lists or items", required: false
  param :description, desc: "Description for new lists or items", required: false
  param :list_id, desc: "ID or title reference to existing list", required: false
  param :item_id, desc: "ID of the item to modify", required: false
  param :parent_list_id, desc: "Parent list ID when creating sub-lists", required: false
  param :sub_lists, desc: "Array of sub-list data or comma-separated string of cities/names when creating multiple lists", required: false

  def initialize(user, context = {})
    @user = user
    @context = context
  end

  def execute(action:, **params)
    case action
    when "create_list"
      create_list(params[:title], params[:description])
    when "create_sub_lists"
      create_sub_lists(params[:parent_list_id], params[:sub_lists])
    when "add_item"
      add_item(params[:list_id], params[:title], params[:description])
    when "get_lists"
      get_lists
    when "get_list_items"
      get_list_items(params[:list_id])
    when "complete_item"
      complete_item(params[:item_id])
    else
      { success: false, error: "Unknown action: #{action}" }
    end
    # RubyLLM 1.8 handles errors automatically - no manual rescue needed
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

  def create_sub_lists(parent_list_id, sub_lists_data)
    parent_list = find_list(parent_list_id) if parent_list_id && parent_list_id != "most_recent"

    # Handle different input formats for sub_lists_data
    sub_lists_array = normalize_sub_lists_input(sub_lists_data)

    return { success: false, error: "No sub-lists data provided" } if sub_lists_array.empty?

    created_lists = []

    sub_lists_array.each do |sub_list_info|
      # Handle both hash format and string format
      if sub_list_info.is_a?(String)
        # For roadshow cities, create default planning items
        list_title = "#{sub_list_info} - Roadshow Planning"
        list_description = "Planning checklist for #{sub_list_info} roadshow stop"

        list = @user.lists.create!(
          title: list_title,
          description: list_description,
          status: "active"
        )

        # Add default roadshow planning items
        default_roadshow_items = [
          "Venue research and booking",
          "Local partnership outreach",
          "Marketing and promotion planning",
          "Travel and accommodation arrangements",
          "Equipment and materials shipping",
          "Local team coordination",
          "Post-event follow-up planning"
        ]

        default_roadshow_items.each_with_index do |item_title, index|
          list.list_items.create!(
            title: item_title,
            position: index
          )
        end
      else
        # Handle hash format
        list = @user.lists.create!(
          title: sub_list_info[:title] || sub_list_info["title"],
          description: sub_list_info[:description] || sub_list_info["description"],
          status: "active"
        )

        # Add items to sub-list if provided
        if sub_list_info[:items] || sub_list_info["items"]
          items_data = sub_list_info[:items] || sub_list_info["items"]
          items_data.each_with_index do |item_data, index|
            list.list_items.create!(
              title: item_data[:title] || item_data["title"] || item_data,
              description: item_data[:description] || item_data["description"],
              position: index
            )
          end
        end
      end

      broadcast_list_update(list)
      created_lists << serialize_list(list)
    end

    {
      success: true,
      message: "Created #{created_lists.length} sub-lists#{parent_list ? " under '#{parent_list.title}'" : ""}",
      lists: created_lists,
      parent_list: parent_list ? serialize_list(parent_list) : nil
    }
  end

  def normalize_sub_lists_input(input)
    return [] if input.nil? || input.empty?

    case input
    when String
      # Handle comma-separated string like "San Francisco, New York, Austin"
      input.split(",").map(&:strip).reject(&:empty?)
    when Array
      input
    else
      []
    end
  end

  def add_item(list_id, title, description = nil)
    list = find_list(list_id)
    return { success: false, error: "List not found" } unless list

    item = list.list_items.create!(
      title: title,
      description: description,
      position: list.list_items.count
    )

    broadcast_item_update(item)

    {
      success: true,
      message: "Added item '#{title}' to '#{list.title}'",
      item: serialize_item(item),
      list: serialize_list(list)
    }
  end

  def get_lists
    lists = @user.lists.recent.limit(20)

    {
      success: true,
      message: "Retrieved #{lists.count} lists",
      lists: lists.map { |list| serialize_list(list) }
    }
  end

  def get_list_items(list_id)
    list = find_list(list_id)
    return { success: false, error: "List not found" } unless list

    items = list.list_items.order(:position)

    {
      success: true,
      message: "Retrieved #{items.count} items from '#{list.title}'",
      list: serialize_list(list),
      items: items.map { |item| serialize_item(item) }
    }
  end

  def complete_item(item_id)
    item = @user.list_items.joins(:list).find_by(id: item_id)
    return { success: false, error: "Item not found" } unless item

    item.update!(status: "completed")
    broadcast_item_update(item)

    {
      success: true,
      message: "Marked '#{item.title}' as completed",
      item: serialize_item(item)
    }
  end

  def find_list(list_id)
    return nil if list_id.nil? || list_id.empty?

    # Handle special case for "most_recent"
    return @user.lists.order(:updated_at).last if list_id == "most_recent"

    if list_id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
      @user.lists.find_by(id: list_id)
    else
      @user.lists.find_by("title ILIKE ?", "%#{list_id}%")
    end
  end

  def serialize_list(list)
    {
      id: list.id,
      title: list.title,
      description: list.description,
      status: list.status,
      items_count: list.list_items.count,
      created_at: list.created_at,
      updated_at: list.updated_at
    }
  end

  def serialize_item(item)
    {
      id: item.id,
      title: item.title,
      description: item.description,
      status: item.status,
      priority: item.priority,
      position: item.position,
      list_id: item.list_id,
      created_at: item.created_at,
      updated_at: item.updated_at
    }
  end

  def broadcast_list_update(list)
    # Turbo Stream broadcasts for real-time updates
    Turbo::StreamsChannel.broadcast_replace_to(
      "user_#{@user.id}_lists",
      target: "lists",
      partial: "lists/list_cards",
      locals: { lists: @user.lists.recent.limit(20) }
    )
  rescue => e
    Rails.logger.error "Failed to broadcast list update: #{e.message}"
    # Don't let broadcast errors break the main functionality
  end

  def broadcast_item_update(item)
    # Turbo Stream broadcasts for real-time updates
    Turbo::StreamsChannel.broadcast_replace_to(
      "user_#{@user.id}_list_#{item.list_id}",
      target: "list_items",
      partial: "list_items/item_cards",
      locals: { items: item.list.list_items.order(:position) }
    )
  rescue => e
    Rails.logger.error "Failed to broadcast item update: #{e.message}"
    # Don't let broadcast errors break the main functionality
  end
end
