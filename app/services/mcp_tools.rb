# app/services/mcp_tools.rb
class McpTools
  def initialize(user, context = {})
    @user = user
    @context = context
  end

  def available_tools
    [
      create_list_tool,
      add_items_to_list_tool,
      complete_items_tool,
      get_list_info_tool,
      share_list_tool,
      search_lists_tool,
      get_current_list_tool
    ]
  end

  def call_tool(function_name, arguments)
    case function_name
    when 'create_list'
      create_list(arguments)
    when 'add_items_to_list'
      add_items_to_list(arguments)
    when 'complete_items'
      complete_items(arguments)
    when 'get_list_info'
      get_list_info(arguments)
    when 'share_list'
      share_list(arguments)
    when 'search_lists'
      search_lists(arguments)
    when 'get_current_list'
      get_current_list(arguments)
    else
      { error: "Unknown function: #{function_name}" }
    end
  end

  private

  # Tool definitions
  def create_list_tool
    {
      type: "function",
      function: {
        name: "create_list",
        description: "Create a new list for the user",
        parameters: {
          type: "object",
          properties: {
            title: { type: "string", description: "The title of the list" },
            description: { type: "string", description: "Optional description of the list" },
            items: {
              type: "array",
              items: { type: "string" },
              description: "Optional array of initial items to add to the list"
            }
          },
          required: ["title"]
        }
      }
    }
  end

  def add_items_to_list_tool
    {
      type: "function",
      function: {
        name: "add_items_to_list",
        description: "Add items to an existing list",
        parameters: {
          type: "object",
          properties: {
            list_id: { type: "string", description: "The ID of the list to add items to" },
            items: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  title: { type: "string", description: "The item title" },
                  description: { type: "string", description: "Optional item description" },
                  item_type: {
                    type: "string",
                    enum: ["task", "note", "link", "file", "reminder"],
                    description: "The type of item"
                  },
                  priority: {
                    type: "string",
                    enum: ["low", "medium", "high", "urgent"],
                    description: "The priority level"
                  },
                  due_date: { type: "string", description: "Optional due date (ISO format)" }
                },
                required: ["title"]
              }
            }
          },
          required: ["list_id", "items"]
        }
      }
    }
  end

  def complete_items_tool
    {
      type: "function",
      function: {
        name: "complete_items",
        description: "Mark items as completed",
        parameters: {
          type: "object",
          properties: {
            list_id: { type: "string", description: "The ID of the list" },
            item_ids: {
              type: "array",
              items: { type: "string" },
              description: "Array of item IDs to mark as completed"
            }
          },
          required: ["list_id", "item_ids"]
        }
      }
    }
  end

  def get_list_info_tool
    {
      type: "function",
      function: {
        name: "get_list_info",
        description: "Get detailed information about a list and its items",
        parameters: {
          type: "object",
          properties: {
            list_id: { type: "string", description: "The ID of the list" }
          },
          required: ["list_id"]
        }
      }
    }
  end

  def share_list_tool
    {
      type: "function",
      function: {
        name: "share_list",
        description: "Share a list with another user",
        parameters: {
          type: "object",
          properties: {
            list_id: { type: "string", description: "The ID of the list to share" },
            email: { type: "string", description: "Email address of the user to share with" },
            permission: {
              type: "string",
              enum: ["read", "collaborate"],
              description: "Permission level to grant"
            }
          },
          required: ["list_id", "email", "permission"]
        }
      }
    }
  end

  def search_lists_tool
    {
      type: "function",
      function: {
        name: "search_lists",
        description: "Search through user's accessible lists",
        parameters: {
          type: "object",
          properties: {
            query: { type: "string", description: "Search query" },
            status: {
              type: "string",
              enum: ["draft", "active", "completed", "archived"],
              description: "Filter by list status"
            }
          },
          required: ["query"]
        }
      }
    }
  end

  def get_current_list_tool
    {
      type: "function",
      function: {
        name: "get_current_list",
        description: "Get information about the list the user is currently viewing",
        parameters: {
          type: "object",
          properties: {},
          required: []
        }
      }
    }
  end

  # Tool implementations
  def create_list(args)
    list = @user.lists.create!(
      title: args['title'],
      description: args['description'],
      status: 'active'
    )

    # Add initial items if provided
    if args['items'].present?
      args['items'].each do |item_title|
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
      items_added: args['items']&.count || 0,
      message: "Created list '#{list.title}' with #{args['items']&.count || 0} items"
    }
  end

  def add_items_to_list(args)
    list = authorize_list_access!(args['list_id'], :collaborate)

    added_items = []
    args['items'].each do |item_data|
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

  def complete_items(args)
    list = authorize_list_access!(args['list_id'], :collaborate)

    items = list.list_items.where(id: args['item_ids'])
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

  def get_list_info(args)
    list = authorize_list_access!(args['list_id'], :read)

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

  def share_list(args)
    list = authorize_list_ownership!(args['list_id'])

    result = ListSharingService.new(list, @user)
                              .share_with_email(args['email'], permission: args['permission'])

    if result.success?
      {
        success: true,
        list_title: list.title,
        shared_with: args['email'],
        permission: args['permission'],
        message: "Shared '#{list.title}' with #{args['email']} (#{args['permission']} access)"
      }
    else
      {
        success: false,
        error: result.errors,
        message: "Failed to share list: #{result.errors}"
      }
    end
  end

  def search_lists(args)
    lists = @user.accessible_lists.includes(:list_items, :owner)

    # Apply search query
    if args['query'].present?
      lists = lists.where("title ILIKE ? OR description ILIKE ?",
                         "%#{args['query']}%", "%#{args['query']}%")
    end

    # Apply status filter
    if args['status'].present?
      lists = lists.where(status: args['status'])
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
      query: args['query'],
      status_filter: args['status'],
      lists: lists_data,
      count: lists_data.count,
      message: "Found #{lists_data.count} lists matching '#{args['query']}'"
    }
  end

  def get_current_list(args)
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
