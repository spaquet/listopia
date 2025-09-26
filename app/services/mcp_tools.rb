# app/services/mcp_tools.rb
class McpTools
  def initialize(user, context = {})
    @user = user
    @context = context
  end

  def execute(action:, **params)
    case action.to_s
    when "create_list"
      create_list(**params)
    when "create_list_with_sublists"
      create_list_with_sublists(**params)
    when "add_item"
      add_item(**params)
    when "get_lists"
      get_lists(**params)
    else
      { success: false, error: "Unknown action: #{action}" }
    end
  end

  private

  def create_list(title:, description: nil, category: "personal", **_unused)
    return validation_error("Title is required") if title.blank?

    begin
      list = @user.lists.create!(
        title: title.to_s.strip,
        description: description&.to_s&.strip,
        category: category.to_s,
        status: "active"
      )

      success_response(
        "Created list '#{list.title}'",
        list: format_list_data(list)
      )
    rescue ActiveRecord::RecordInvalid => e
      validation_error("Failed to create list: #{e.message}")
    rescue => e
      Rails.logger.error "List creation failed: #{e.message}"
      error_response("Failed to create list. Please try again.")
    end
  end

  def create_list_with_sublists(title:, description: nil, sublists: [], category: "personal", **_unused)
    return validation_error("Title is required") if title.blank?
    return validation_error("At least one sublist is required") if sublists.empty?

    begin
      ActiveRecord::Base.transaction do
        # Create main list
        main_list = @user.lists.create!(
          title: title.to_s.strip,
          description: description&.to_s&.strip,
          category: category.to_s,
          status: "active"
        )

        # Create sublists
        created_sublists = sublists.map do |sublist_data|
          sublist_title = sublist_data.is_a?(Hash) ? sublist_data[:title] || sublist_data["title"] : sublist_data.to_s
          sublist_description = sublist_data.is_a?(Hash) ? sublist_data[:description] || sublist_data["description"] : nil

          next if sublist_title.blank?

          @user.lists.create!(
            title: sublist_title.strip,
            description: sublist_description&.strip,
            parent_list: main_list,
            category: category.to_s,
            status: "active"
          )
        end.compact

        success_response(
          "Created list '#{main_list.title}' with #{created_sublists.count} sublists",
          main_list: format_list_data(main_list),
          sublists: created_sublists.map { |sl| format_list_data(sl) }
        )
      end
    rescue ActiveRecord::RecordInvalid => e
      validation_error("Failed to create lists: #{e.message}")
    rescue => e
      Rails.logger.error "Complex list creation failed: #{e.message}"
      error_response("Failed to create lists. Please try again.")
    end
  end

  def add_item(list_id: nil, list_title: nil, content:, priority: "medium", **_unused)
    return validation_error("Content is required") if content.blank?

    begin
      # Find the list
      list = find_list(list_id: list_id, list_title: list_title)
      return list if list[:success] == false # Return error if list not found

      target_list = list[:list]

      # Create the item
      item = target_list.list_items.create!(
        content: content.to_s.strip,
        priority: priority.to_s,
        status: "pending"
      )

      success_response(
        "Added item '#{item.content}' to list '#{target_list.title}'",
        item: format_item_data(item),
        list: format_list_data(target_list)
      )
    rescue ActiveRecord::RecordInvalid => e
      validation_error("Failed to add item: #{e.message}")
    rescue => e
      Rails.logger.error "Item creation failed: #{e.message}"
      error_response("Failed to add item. Please try again.")
    end
  end

  def get_lists(include_items: false, **_unused)
    begin
      lists = @user.lists.includes(include_items ? :list_items : [])
                   .where(parent_list: nil) # Only top-level lists
                   .order(updated_at: :desc)
                   .limit(20)

      if lists.empty?
        return success_response(
          "No lists found. You can create your first list!",
          lists: [],
          count: 0
        )
      end

      formatted_lists = lists.map do |list|
        list_data = format_list_data(list)
        if include_items
          list_data[:items] = list.list_items.order(created_at: :desc).map { |item| format_item_data(item) }
        end
        list_data
      end

      success_response(
        "Found #{lists.count} list#{lists.count == 1 ? '' : 's'}",
        lists: formatted_lists,
        count: lists.count
      )
    rescue => e
      Rails.logger.error "List retrieval failed: #{e.message}"
      error_response("Failed to retrieve lists. Please try again.")
    end
  end

  def find_list(list_id: nil, list_title: nil)
    if list_id.present?
      list = @user.lists.find_by(id: list_id)
      return validation_error("List not found with ID: #{list_id}") unless list
    elsif list_title.present?
      list = @user.lists.where("title ILIKE ?", "%#{list_title}%").first
      return validation_error("List not found with title containing: '#{list_title}'") unless list
    else
      return validation_error("Either list_id or list_title is required")
    end

    { success: true, list: list }
  end

  def format_list_data(list)
    {
      id: list.id,
      title: list.title,
      description: list.description,
      category: list.category,
      status: list.status,
      items_count: list.list_items.count,
      created_at: list.created_at.strftime("%Y-%m-%d %H:%M"),
      has_sublists: list.child_lists.any?
    }
  end

  def format_item_data(item)
    {
      id: item.id,
      content: item.content,
      priority: item.priority,
      status: item.status,
      created_at: item.created_at.strftime("%Y-%m-%d %H:%M")
    }
  end

  def success_response(message, **data)
    {
      success: true,
      message: message,
      timestamp: Time.current.strftime("%Y-%m-%d %H:%M:%S")
    }.merge(data)
  end

  def validation_error(message)
    {
      success: false,
      error: message,
      type: "validation_error",
      timestamp: Time.current.strftime("%Y-%m-%d %H:%M:%S")
    }
  end

  def error_response(message)
    {
      success: false,
      error: message,
      type: "system_error",
      timestamp: Time.current.strftime("%Y-%m-%d %H:%M:%S")
    }
  end
end
