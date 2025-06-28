# app/services/mcp_service.rb
class McpService
  include ActiveModel::Model
  include ActiveModel::Attributes

  attr_accessor :user, :context, :chat

  def initialize(user:, context: {}, chat: nil)
    @user = user
    @context = context
    @chat = chat || user.current_chat
    @tools = McpTools.new(user, context)
  end

  def process_message(message_content)
    start_time = Time.current

    # Ensure user is authenticated
    raise AuthorizationError, "User must be authenticated" unless @user

    # Check rate limits
    rate_limiter = McpRateLimiter.new(@user)
    rate_limiter.check_rate_limit!

    # Validate message length
    if message_content.length > Rails.application.config.mcp.max_message_length
      raise ValidationError, "Message is too long (max #{Rails.application.config.mcp.max_message_length} characters)"
    end

    # Save user message to database
    user_message = @chat.add_user_message(message_content, context: @context)

    # Build conversation history
    conversation = build_conversation_history

    # Get LLM response with tools
    llm_response = RubyLlm.chat(
      messages: conversation,
      tools: @tools.available_tools,
      tool_choice: "auto",
      model: Rails.application.config.mcp.model,
      provider: Rails.application.config.mcp.provider
    )

    # Process tool calls if any
    tool_results = process_tool_calls(llm_response)

    # Extract assistant response
    assistant_content = extract_assistant_content(llm_response)

    # Save assistant message to database
    processing_time = Time.current - start_time
    assistant_message = @chat.add_assistant_message(
      assistant_content,
      tool_calls: extract_tool_calls(llm_response),
      tool_results: tool_results,
      metadata: {
        llm_provider: Rails.application.config.mcp.provider,
        llm_model: Rails.application.config.mcp.model,
        processing_time: processing_time,
        context_snapshot: @context
      }
    )

    # Update message metadata
    assistant_message.update!(
      llm_provider: Rails.application.config.mcp.provider,
      llm_model: Rails.application.config.mcp.model,
      processing_time: processing_time
    )

    # Increment rate limit counters after successful processing
    rate_limiter.increment_counters!

    assistant_content

  rescue McpRateLimiter::RateLimitError => e
    e.message
  rescue ValidationError => e
    e.message
  rescue => e
    Rails.logger.error "MCP Error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    # Save error message to chat
    @chat.add_assistant_message(
      "I apologize, but I encountered an error processing your request. Please try again.",
      metadata: { error: e.message, error_class: e.class.name }
    )

    "I apologize, but I encountered an error processing your request. Please try again."
  end

  private

  def build_conversation_history
    # Start with system message
    messages = [{
      role: "system",
      content: build_system_prompt
    }]

    # Add recent conversation history
    recent_messages = @chat.latest_messages(20) # Last 20 messages
    messages += recent_messages.map(&:to_llm_format)

    # Add current context
    if @context.present?
      messages << {
        role: "user",
        content: "Current context: #{build_context_message}"
      }
    end

    messages
  end

  def build_system_prompt
    <<~PROMPT
      You are Listopia Assistant, an AI helper for the Listopia list management application.

      You can help users:
      - Create and manage lists
      - Add, update, and complete items
      - Share lists with collaborators
      - Analyze list progress and productivity
      - Set priorities and due dates

      CRITICAL AUTHORIZATION RULES:
      - Users can only access lists they own or have been invited to collaborate on
      - Read permission allows viewing lists and items
      - Collaborate permission allows editing lists and items
      - Only list owners can delete lists or manage collaborations
      - Always verify permissions before taking any action

      When using tools:
      1. Always check user permissions first
      2. Provide helpful, context-aware responses
      3. If you cannot perform an action due to permissions, explain why
      4. Suggest alternatives when possible
      5. Use the available tools to perform requested actions

      Current user context: #{@context['page'] || 'general'}

      Respond naturally and conversationally. Use the provided tools to perform actions when requested.
    PROMPT
  end

  def build_context_message
    return "No additional context available." if @context.blank?

    context_parts = []

    if @context['page']
      context_parts << "User is currently on page: #{@context['page']}"
    end

    if @context['list_id']
      context_parts << "User is viewing list: #{@context['list_title']} (ID: #{@context['list_id']})"
      context_parts << "List has #{@context['items_count']} items, #{@context['completed_count']} completed"
      context_parts << "User #{@context['is_owner'] ? 'owns' : 'collaborates on'} this list"
      context_parts << "User #{@context['can_collaborate'] ? 'can edit' : 'can only view'} this list"
    end

    if @context['total_lists']
      context_parts << "User has access to #{@context['total_lists']} total lists"
    end

    context_parts.join('. ')
  end

  def process_tool_calls(llm_response)
    tool_calls = extract_tool_calls(llm_response)
    return [] unless tool_calls.any?

    tool_calls.map do |tool_call|
      begin
        function_name = tool_call['function']['name']
        arguments = JSON.parse(tool_call['function']['arguments'])

        # Execute the tool via ruby_llm tools
        result = @tools.call_tool(function_name, arguments)

        {
          tool_call_id: tool_call['id'],
          function_name: function_name,
          arguments: arguments,
          result: result,
          success: true
        }
      rescue => e
        Rails.logger.error "Tool call error: #{e.message}"
        {
          tool_call_id: tool_call['id'],
          function_name: function_name,
          arguments: arguments,
          result: { error: e.message },
          success: false
        }
      end
    end
  end

  def extract_tool_calls(llm_response)
    llm_response.dig('choices', 0, 'message', 'tool_calls') || []
  end

  def extract_assistant_content(llm_response)
    content = llm_response.dig('choices', 0, 'message', 'content')

    # If no content but there were tool calls, provide a default response
    if content.blank? && extract_tool_calls(llm_response).any?
      "I've processed your request. Please check for any updates."
    else
      content || "I've received your message and processed it."
    end
  end

  class AuthorizationError < StandardError; end
  class ValidationError < StandardError; end
end manage collaborations
      - Always verify permissions before taking any action

      When using tools:
      1. Always check user permissions first
      2. Provide helpful, context-aware responses
      3. If you cannot perform an action due to permissions, explain why
      4. Suggest alternatives when possible

      Respond naturally and conversationally. Use the provided tools to perform actions when requested.
    PROMPT
  end

  def build_context_message
    return "No additional context available." if @context.blank?

    context_parts = []

    if @context['page']
      context_parts << "User is currently on page: #{@context['page']}"
    end

    if @context['list_id']
      context_parts << "User is viewing list: #{@context['list_title']} (ID: #{@context['list_id']})"
      context_parts << "List has #{@context['items_count']} items, #{@context['completed_count']} completed"
      context_parts << "User #{@context['is_owner'] ? 'owns' : 'collaborates on'} this list"
      context_parts << "User #{@context['can_collaborate'] ? 'can edit' : 'can only view'} this list"
    end

    if @context['total_lists']
      context_parts << "User has access to #{@context['total_lists']} total lists"
    end

    "Current context: #{context_parts.join('. ')}"
  end

  def available_tools
    [
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
      },
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
      },
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
      },
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
      },
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
      },
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
    ]
  end

  def process_tool_calls(llm_response)
    tool_calls = extract_tool_calls(llm_response)

    tool_calls.each do |tool_call|
      function_name = tool_call['function']['name']
      arguments = JSON.parse(tool_call['function']['arguments'])

      result = execute_function(function_name, arguments)

      # Add tool result to conversation context if needed
      # This could be used for multi-step operations
    end
  end

  def extract_tool_calls(llm_response)
    # Extract tool calls from LLM response
    # Implementation depends on ruby_llm response format
    llm_response.dig('choices', 0, 'message', 'tool_calls') || []
  end

  def extract_assistant_message(llm_response)
    # Extract the assistant's text response
    llm_response.dig('choices', 0, 'message', 'content') ||
      "I've processed your request. Please check your lists for any updates."
  end

  def execute_function(function_name, arguments)
    case function_name
    when 'create_list'
      create_list_function(arguments)
    when 'add_items_to_list'
      add_items_to_list_function(arguments)
    when 'complete_items'
      complete_items_function(arguments)
    when 'get_list_info'
      get_list_info_function(arguments)
    when 'share_list'
      share_list_function(arguments)
    when 'search_lists'
      search_lists_function(arguments)
    else
      raise "Unknown function: #{function_name}"
    end
  end

  # MCP Function Implementations with Authorization

  def create_list_function(args)
    # Any authenticated user can create a list
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

    { success: true, list_id: list.id, message: "Created list '#{list.title}'" }
  end

  def add_items_to_list_function(args)
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
      items_added: added_items.count,
      message: "Added #{added_items.count} items to '#{list.title}'"
    }
  end

  def complete_items_function(args)
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
      completed_count: completed_count,
      message: "Marked #{completed_count} items as completed in '#{list.title}'"
    }
  end

  def get_list_info_function(args)
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
        items: items.map do |item|
          {
            id: item.id,
            title: item.title,
            completed: item.completed?,
            item_type: item.item_type,
            priority: item.priority,
            due_date: item.due_date&.iso8601,
            assigned_to: item.assigned_user&.name
          }
        end
      }
    }
  end

  def share_list_function(args)
    list = authorize_list_ownership!(args['list_id'])

    result = ListSharingService.new(list, @user)
                              .share_with_email(args['email'], permission: args['permission'])

    if result.success?
      {
        success: true,
        message: "Shared '#{list.title}' with #{args['email']} (#{args['permission']} access)"
      }
    else
      {
        success: false,
        message: "Failed to share list: #{result.errors}"
      }
    end
  end

  def search_lists_function(args)
    lists = @user.accessible_lists

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
        status: list.status,
        items_count: list.list_items.count,
        is_owner: list.owner == @user
      }
    end

    {
      success: true,
      lists: lists_data,
      count: lists_data.count
    }
  end

  # Authorization Methods

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
  class ValidationError < StandardError; end
end
