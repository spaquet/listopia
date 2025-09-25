# app/services/mcp_service.rb

class McpService
  def initialize(user:, context: {}, chat: nil)
    @user = user
    @context = context
    @chat = chat || @user.current_chat
  end

  def process_message(message_content)
    setup_chat
    response = @chat.ask(message_content)
    response.content
  rescue => e
    Rails.logger.error "MCP Error: #{e.message}"
    handle_error(e)
  end

  private

  def setup_chat
    # Use RubyLLM 1.8 standard approach
    @chat.with_instructions(build_system_instructions)
    @chat.with_tool(ListManagementTool.new(@user, @context))
  end

  def build_system_instructions
    <<~INSTRUCTIONS
      You are an AI assistant integrated with Listopia, a collaborative list management application.

      You can help users manage their lists, create items, update tasks, and collaborate with others.

      CURRENT CONTEXT:
      #{build_context_summary}

      When the user refers to 'this list', 'these items', 'first 3 items', etc., use the context above to resolve these references.

      IMPORTANT: Listopia is fundamentally a planning and organization tool.
      When users ask for help with planning, organizing, or managing tasks:
      1. CREATE concrete, actionable lists using the available tools
      2. ORGANIZE information into clear, structured formats
      3. SUGGEST workflows and processes that help users stay organized
      4. USE the list and item management tools to create tangible outcomes

      Always aim to provide practical, organized solutions that users can immediately act upon.

      Current page context: #{@context[:page] || 'unknown'}
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

    # Get recent list context
    if recent_list = @user.lists.order(:updated_at).last
      context_parts << "Most recent list: #{recent_list.title}"
    end

    context_parts.join(", ")
  end

  def handle_error(error)
    case error
    when ActiveRecord::StatementInvalid
      if error.message.include?("tool_messages_must_have_tool_call_id")
        Rails.logger.error "Database constraint violation - this should not happen with RubyLLM 1.8"
        "I encountered a technical issue. Please try again."
      else
        "I encountered a database error. Please try again."
      end
    when RubyLLM::Error
      "I encountered an AI service error. Please try again."
    else
      "I apologize, but I encountered an error processing your request."
    end
  end
end
