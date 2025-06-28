# app/services/mcp_tools.rb
class McpTools
  include RubyLlm::Tools

  def initialize(user, context = {})
    @user = user
    @context = context
  end

  # Tool: Create a new list
  tool :create_list do
    description "Create a new list for the user"

    parameter :title, type: :string, description: "The title of the list", required: true
    parameter :description, type: :string, description: "Optional description of the list"
    parameter :items, type: :array, description: "Optional array of initial items to add to the list",
              items: { type: :string }

    def call(title:, description: nil, items: [])
      list = @user.lists.create!(
        title: title,
        description: description,
        status: 'active'
      )

      # Add initial items if provided
      if items.any?
        items.each do |item_title|
          list.list_items.create!(
            title: item_title,
            item_type: 'task',
            priority: 'medium'
          )
        end
      end

      {
        success: true,
        list_id: list.id,
        title: list.title,
        items_added: items.count,
        message: "Created list '#{list.title}' with #{items.count} items"
      }
    end
  end

  # Tool: Add items to an existing list
  tool :add_items_to_list do
    description "Add items to an existing list"

    parameter :list_id, type: :string, description: "The ID of the list to add items to", required: true
    parameter :items, type: :array, description: "Array of items to add", required: true,
              items: {
                type: :object,
                properties: {
                  title: { type: :string, description: "The item title" },
                  description: { type: :string, description: "Optional item description" },
                  item_type: {
                    type: :string,
                    enum: ["task", "note", "link", "file", "reminder"],
                    description: "The type of item"
                  },
                  priority: {
                    type: :string,
                    enum: ["low", "medium", "high", "urgent"],
                    description: "The priority level"
                  },
                  due_date: { type: :string, description: "Optional due date (ISO format)" }
                },
                required: ["title"]
              }

    def call(list_id:, items:)
      list = authorize_list_access!(list_id, :collaborate)

      added_items = []
      items.each do |item_data|
        item = list.list_items.create!(
          title: item_data['title'],
          description: item_data['description'],
          item_type: item_data['item_type'] || 'task',
          priority: item_data['priority'] || 'medium',
          due_date: item_data['due_date'] ? Time.parse(item_data['due_date']) : nil
        )
        added_items << item
      end

      {
        success: true,
        list_title: list.title,
        items_added: added_items.count,
        message: "Added #{added_items.count} items to '#{list.title}'"
      }
    end
  end

  # Tool: Complete items
  tool :complete_items do
    description "Mark items as completed"

    parameter :list_id, type: :string, description: "The ID of the list", required: true
    parameter :item_ids, type: :array, description: "Array of item IDs to mark as completed", required: true,
              items: { type: :string }

    def call(list_id:, item_ids:)
      list = authorize_list_access!(list_id, :collaborate)

      items = list.list_items.where(id: item_ids)
      completed_count = 0

      items.each do |item|
        if item.update(completed: true, completed_at: Time.current)
          completed_count += 1
        end
      end

      {
        success: true,
        list_title: list.title,
        completed_count: completed_count,
        message: "Marked #{completed_count} items as completed in '#{list.title}'"
      }
    end
  end

  # Tool: Get list information
  tool :get_list_info do
    description "Get detailed information about a list and its items"

    parameter :list_id, type: :string, description: "The ID of the list", required: true

    def call(list_id:)
      list = authorize_list_access!(list_id, :read)

      items = list.list_items.includes(:assigned_user)

      {
        success: true,
        list: {
          id: list.id,
          title: list.title,
          description: list.description,
          status: list.status,
          items_count: items.count,
          completed_count: items.completed.count,
          is_owner: list.owner == @user,
          can_collaborate: list.collaboratable_by?(@user),
          items: items.order(:position, :created_at).map do |item|
            {
              id: item.id,
              title: item.title,
              description: item.description,
              completed: item.completed?,
              item_type: item.item_type,
              priority: item.priority,
              due_date: item.due_date&.iso8601,
              assigned_to: item.assigned_user&.name,
              position: item.position
            }
          end
        }
      }
    end
  end

  # Tool: Share list
  tool :share_list do
    description "Share a list with another user"

    parameter :list_id, type: :string, description: "The ID of the list to share", required: true
    parameter :email, type: :string, description: "Email address of the user to share with", required: true
    parameter :permission, type: :string, description: "Permission level to grant", required: true,
              enum: ["read", "collaborate"]

    def call(list_id:, email:, permission:)
      list = authorize_list_ownership!(list_id)

      result = ListSharingService.new(list, @user)
                                .share_with_email(email, permission: permission)

      if result.success?
        {
          success: true,
          list_title: list.title,
          shared_with: email,
          permission: permission,
          message: "Shared '#{list.title}' with #{email} (#{permission} access)"
        }
      else
        {
          success: false,
          error: result.errors,
          message: "Failed to share list: #{result.errors}"
        }
      end
    end
  end

  # Tool: Search lists
  tool :search_lists do
    description "Search through user's accessible lists"

    parameter :query, type: :string, description: "Search query", required: true
    parameter :status, type: :string, description: "Filter by list status",
              enum: ["draft", "active", "completed", "archived"]

    def call(query:, status: nil)
      lists = @user.accessible_lists.includes(:list_items, :owner)

      # Apply search query
      if query.present?
        lists = lists.where("title ILIKE ? OR description ILIKE ?",
                           "%#{query}%", "%#{query}%")
      end

      # Apply status filter
      if status.present?
        lists = lists.where(status: status)
      end

      lists_data = lists.limit(10).map do |list|
        {
          id: list.id,
          title: list.title,
          description: list.description,
          status: list.status,
          items_count: list.list_items.count,
          completed_count: list.list_items.completed.count,
          is_owner: list.owner == @user,
          can_collaborate: list.collaboratable_by?(@user),
          last_updated: list.updated_at.iso8601
        }
      end

      {
        success: true,
        query: query,
        status_filter: status,
        lists: lists_data,
        count: lists_data.count,
        message: "Found #{lists_data.count} lists matching '#{query}'"
      }
    end
  end

  # Tool: Get current context list (if viewing a list)
  tool :get_current_list do
    description "Get information about the list the user is currently viewing"

    def call
      if @context['list_id']
        list = authorize_list_access!(@context['list_id'], :read)

        {
          success: true,
          current_list: {
            id: list.id,
            title: list.title,
            items_count: @context['items_count'],
            completed_count: @context['completed_count'],
            is_owner: @context['is_owner'],
            can_collaborate: @context['can_collaborate']
          },
          message: "You are currently viewing '#{list.title}'"
        }
      else
        {
          success: false,
          message: "You are not currently viewing a specific list"
        }
      end
    end
  end

  private

  def authorize_list_access!(list_id, required_permission)
    list = @user.accessible_lists.find(list_id)

    case required_permission
    when :read
      unless list.readable_by?(@user)
        raise AuthorizationError, "You don't have permission to view this list"
      end
    when :collaborate
      unless list.collaboratable_by?(@user)
        raise AuthorizationError, "You don't have permission to edit this list"
      end
    end

    list
  rescue ActiveRecord::RecordNotFound
    raise AuthorizationError, "List not found or access denied"
  end

  def authorize_list_ownership!(list_id)
    list = @user.lists.find(list_id)
    list
  rescue ActiveRecord::RecordNotFound
    raise AuthorizationError, "You can only perform this action on lists you own"
  end

  class AuthorizationError < StandardError; end
end
