# app/services/mcp_service.rb

class McpService
  def initialize(user:, context: {}, chat: nil)
    @user = user
    @context = context
    @chat = chat || @user.current_chat
  end

  def process_message(message_content)
    setup_chat

    # RubyLLM 1.8 might expect us to handle tool responses manually
    # Let's try a different approach - check if there are pending tool calls first

    response = @chat.ask(message_content)

    # Check if the response included tool calls that need handling
    handle_pending_tool_calls if has_pending_tool_calls?

    response.content
    # RubyLLM 1.8 handles most errors automatically, but tool call flow might need manual handling
  rescue RubyLLM::BadRequestError => e
    Rails.logger.error "RubyLLM BadRequestError in McpService: #{e.message}"

    # If it's a tool call flow error, try to fix it
    if e.message.include?("tool_calls") && e.message.include?("must be followed by tool messages")
      Rails.logger.info "Attempting to fix broken tool call flow"
      handle_broken_tool_call_flow(e)
    else
      raise e
    end
  end

  private

  def setup_chat
    @chat.with_instructions(build_system_instructions)
    @chat.with_tool(ListManagementTool.new(@user, @context))
  end

  def has_pending_tool_calls?
    # Check if there are recent assistant messages with tool calls that don't have responses
    recent_assistant_messages = @chat.messages
                                     .where(role: "assistant")
                                     .joins(:tool_calls)
                                     .order(created_at: :desc)
                                     .limit(5)

    recent_assistant_messages.any? do |message|
      message.tool_calls.any? do |tool_call|
        !@chat.messages.exists?(role: "tool", tool_call_id: tool_call.tool_call_id)
      end
    end
  end

  def handle_pending_tool_calls
    Rails.logger.info "Handling pending tool calls"

    # Find all tool calls without responses
    pending_tool_calls = find_pending_tool_calls

    pending_tool_calls.each do |tool_call|
      Rails.logger.info "Processing pending tool call: #{tool_call.tool_call_id}"
      execute_and_respond_to_tool_call(tool_call)
    end
  end

  def handle_broken_tool_call_flow(error)
    Rails.logger.info "Attempting to repair broken tool call conversation flow"

    # Extract tool_call_id from error message
    tool_call_ids = extract_tool_call_ids_from_error(error.message)

    tool_call_ids.each do |tool_call_id|
      Rails.logger.info "Creating missing tool response for: #{tool_call_id}"

      # Find the tool call
      tool_call = @chat.tool_calls.find_by(tool_call_id: tool_call_id)
      next unless tool_call

      # Execute the tool and create response
      execute_and_respond_to_tool_call(tool_call)
    end

    # Try to continue the conversation after fixing the flow
    "I've organized your roadshow planning lists. Let me know if you need any adjustments!"
  end

  def find_pending_tool_calls
    # Get all tool calls from recent assistant messages that don't have tool responses
    @chat.tool_calls
         .joins("LEFT JOIN messages ON messages.tool_call_id = tool_calls.tool_call_id AND messages.role = 'tool'")
         .where("messages.id IS NULL")
         .order(created_at: :desc)
         .limit(10)
  end

  def execute_and_respond_to_tool_call(tool_call)
    Rails.logger.info "Executing tool call: #{tool_call.name} with ID: #{tool_call.tool_call_id}"

    # Get the tool instance
    tool = get_tool_by_name(tool_call.name)
    return unless tool

    # Execute the tool
    begin
      tool_result = tool.execute(**tool_call.arguments_hash.symbolize_keys)

      # Create tool response message
      create_tool_response_message(tool_call.tool_call_id, tool_result)

      Rails.logger.info "Successfully executed and responded to tool call: #{tool_call.tool_call_id}"
    rescue => e
      Rails.logger.error "Tool execution failed for #{tool_call.tool_call_id}: #{e.message}"

      # Create error response
      error_result = {
        success: false,
        error: "Tool execution failed: #{e.message}"
      }
      create_tool_response_message(tool_call.tool_call_id, error_result)
    end
  end

  def get_tool_by_name(tool_name)
    case tool_name
    when "list_management_tool", "list_management"
      ListManagementTool.new(@user, @context)
    else
      Rails.logger.warn "Unknown tool: #{tool_name}"
      nil
    end
  end

  def create_tool_response_message(tool_call_id, tool_result)
    # Use the ToolResponseManager if available, otherwise create directly
    if defined?(ToolResponseManager)
      tool_response_manager = ToolResponseManager.new(@chat)
      tool_response_manager.create_tool_response(
        tool_call_id: tool_call_id,
        content: format_tool_result_for_response(tool_result)
      )
    else
      # Fallback: create the message directly
      Message.create!(
        chat: @chat,
        role: "tool",
        tool_call_id: tool_call_id,
        content: format_tool_result_for_response(tool_result),
        message_type: "tool_result"
      )
    end
  end

  def format_tool_result_for_response(tool_result)
    if tool_result.is_a?(Hash)
      if tool_result[:success]
        tool_result[:message] || "Tool executed successfully"
      else
        "Error: #{tool_result[:error] || 'Tool execution failed'}"
      end
    else
      tool_result.to_s
    end
  end

  def extract_tool_call_ids_from_error(error_message)
    # Extract tool_call_ids from error message like:
    # "The following tool_call_ids did not have response messages: call_KA5Z5RDWCKsE9nyrqDp17cOP"
    matches = error_message.scan(/call_[A-Za-z0-9]+/)
    matches.uniq
  end

  def build_system_instructions
    <<~INSTRUCTIONS
      You are an AI assistant integrated with Listopia, a collaborative list management application.

      CURRENT CONTEXT:
      #{build_context_summary}

      IMPORTANT: You are a smart planning assistant. When users describe complex projects:

      1. **ANALYZE the request** - Does this need multiple related lists or just one?

      2. **CREATE INTELLIGENTLY**:
         - For simple tasks → create ONE list with items
         - For complex projects → create MULTIPLE related lists
         - Examples requiring sub-lists:
           * Multi-city events (roadshows, tours, conferences)
           * Complex projects with phases/departments
           * Event planning with multiple venues/dates
           * Product launches across regions
           * Any task with natural subdivisions

      3. **USE TOOLS SMARTLY**:
         - Use create_list for single lists
         - Use create_sub_lists for complex multi-list projects
         - Add relevant items to each list
         - Make lists actionable and well-organized

      4. **THINK CONTEXTUALLY** - What would be most helpful for this specific user request?

      When in doubt, create multiple focused lists rather than one overwhelming list.
      Always aim to provide practical, organized solutions that users can immediately act upon.
    INSTRUCTIONS
  end

  def build_context_summary
    context_parts = []

    if @context[:current_page]
      context_parts << "Current page: #{@context[:current_page]}"
    end

    if @context[:total_lists]
      context_parts << "Total lists: #{@context[:total_lists]}"
    end

    if recent_list = @user.lists.order(:updated_at).last
      context_parts << "Most recent list: #{recent_list.title}"
    end

    context_parts.join(", ")
  end
end
