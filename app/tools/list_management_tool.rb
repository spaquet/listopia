# app/tools/list_management_tool.rb
class ListManagementTool < RubyLLM::Tool
  description "Manages lists and list items in Listopia"

  param :action,
    type: :string,
    desc: "The action to perform: 'create_list', 'add_item', 'complete_item', 'get_lists', 'get_list_items'"

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

  def initialize(user, context = {})
    @user = user
    @context = context
  end

  def execute(action:, list_id: nil, title: nil, description: nil, item_id: nil)
    case action
    when "create_list"
      create_list(title, description)
    when "add_item"
      add_item(list_id, title, description)
    when "complete_item"
      complete_item(list_id, item_id)
    when "get_lists"
      get_lists
    when "get_list_items"
      get_list_items(list_id)
    else
      { error: "Unknown action: #{action}. Available actions: create_list, add_item, complete_item, get_lists, get_list_items" }
    end
  rescue => e
    Rails.logger.error "ListManagementTool error: #{e.message}"
    { error: "Failed to #{action}: #{e.message}" }
  end

  private

  def create_list(title, description)
    return { error: "Title is required to create a list" } if title.blank?

    list = @user.lists.create!(
      title: title,
      description: description || "",
      status: :active
    )

    {
      success: true,
      message: "Created list '#{list.title}'",
      list: {
        id: list.id,
        title: list.title,
        description: list.description,
        status: list.status
      }
    }
  end

  def add_item(list_id, title, description)
    return { error: "List ID and title are required to add an item" } if list_id.blank? || title.blank?

    list = find_accessible_list(list_id)
    return { error: "List not found or you don't have permission to edit it" } unless list

    # Check if user can edit this list (owner or collaborator with edit permissions)
    unless can_edit_list?(list)
      return { error: "You don't have permission to add items to this list" }
    end

    item = list.list_items.create!(
      title: title,
      description: description,
      assigned_user: @user,
      item_type: :task,
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

    # Check if user can edit this list
    unless can_edit_list?(list)
      return { error: "You don't have permission to modify items in this list" }
    end

    item = list.list_items.find_by(id: item_id)
    return { error: "Item not found in this list" } unless item

    item.update!(completed: true, completed_at: Time.current)

    {
      success: true,
      message: "Completed item '#{item.title}'",
      item: {
        id: item.id,
        title: item.title,
        completed: item.completed,
        completed_at: item.completed_at
      }
    }
  end

  def get_lists
    lists = @user.accessible_lists.active.recent.limit(20)

    {
      success: true,
      lists: lists.map do |list|
        {
          id: list.id,
          title: list.title,
          description: list.description,
          status: list.status,
          items_count: list.list_items.count,
          completed_count: list.list_items.where(completed: true).count,
          is_owner: list.owner == @user
        }
      end
    }
  end

  def get_list_items(list_id)
    return { error: "List ID is required" } if list_id.blank?

    list = find_accessible_list(list_id)
    return { error: "List not found or you don't have access to it" } unless list

    items = list.list_items.order(:position, :created_at).limit(50)

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
          assigned_user: item.assigned_user&.name
        }
      end
    }
  end

  def find_accessible_list(list_id)
    @user.accessible_lists.find_by(id: list_id)
  end

  def can_edit_list?(list)
    # User is owner
    return true if list.owner == @user

    # User has collaborate permission
    collaboration = list.list_collaborations.find_by(user: @user)
    return false unless collaboration

    # Check if user has collaborate permission (assuming this allows editing)
    collaboration.permission_collaborate?
  end
end
