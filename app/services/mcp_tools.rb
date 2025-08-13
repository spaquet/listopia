# app/services/mcp_tools.rb
class McpTools
  def initialize(user, context = {})
    @user = user
    @context = context

    @context_manager = ConversationContextManager.new(
      user: @user,
      chat: @user.current_chat,
      current_context: @context
    )
  end

  def available_tools
    tools = []

    # List management tool - always available
    tools << ListManagementTool.new(@user, @context)

    # Add more tools as needed
    # tools << CalendarTool.new(@user, @context) if @user.has_calendar_access?
    # tools << EmailTool.new(@user, @context) if @user.has_email_integration?

    tools
  end

  # This method is now deprecated since RubyLLM handles tool calls directly
  # But keeping it for backward compatibility during transition
  def call_tool(function_name, arguments)
    tool = find_tool_by_function_name(function_name)
    return { error: "Tool not found: #{function_name}" } unless tool

    # Convert function name back to method arguments
    method_args = arguments.deep_symbolize_keys

    # Call the tool's execute method
    tool.execute(**method_args)
  end

  private

  def find_tool_by_function_name(function_name)
    # RubyLLM converts class names to snake_case for function names
    # Handle both possible naming conventions
    case function_name
    when "list_management_tool", "list_management"
      ListManagementTool.new(@user, @context)
    else
      nil
    end
  end
end
