# app/services/mcp_service.rb

class McpService
  def initialize(user:, context: {}, chat: nil)
    @user = user
    @context = context
    @chat = chat || @user.current_chat
  end

  def process_message(message_content)
    setup_chat

    # Simple approach - let RubyLLM handle everything
    response = @chat.ask(message_content)

    # Return the content directly
    response.content
  rescue RubyLLM::BadRequestError => e
    Rails.logger.error "RubyLLM BadRequestError in McpService: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    # If it's a tool call flow error, return a helpful message
    if e.message.include?("tool_calls")
      "I encountered an issue while processing your request. Let me help you organize your roadshow planning. What cities would you like to include?"
    else
      "I'm having trouble processing your request right now. Could you please try again?"
    end
  rescue => e
    Rails.logger.error "Unexpected error in McpService: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    "I encountered an unexpected error. Please try your request again."
  end

  private

  def setup_chat
    @chat.with_instructions(build_system_instructions)

    # Try using the tool directly without wrapper
    tool = ListManagementTool.new(@user, @context)
    @chat.with_tool(tool)
  end

  def build_system_instructions
    <<~INSTRUCTIONS
      You are an AI assistant integrated with Listopia, a collaborative list management application.

      ## Tool Capabilities

      You have access to a flexible list management tool that can handle ANY type of list:

      **Actions available:**
      - **create_list**: Create a simple single list
      - **create_list_with_sublists**: Create a main list with multiple sub-lists
      - **add_item**: Add items to any existing list
      - **get_lists**: View all existing lists

      ## Universal Approach

      Lists can be absolutely anything:
      - Shopping lists (groceries, clothes, books)
      - Travel checklists (packing, itinerary, documents)
      - Project planning (any kind of project)
      - Learning goals (courses, skills, books to read)
      - Home maintenance tasks
      - Event planning (parties, meetings, conferences)
      - Health and wellness tracking
      - Creative projects
      - Work tasks and processes
      - Personal goals and habits
      - Anything the user wants to organize

      ## Flexible Workflow

      1. **Listen to what the user wants to organize** - don't assume the structure
      2. **Ask clarifying questions** if you're unsure about the scope or breakdown
      3. **Create appropriate structure**:
         - Simple list for straightforward items
         - Main list + sub-lists for complex multi-part organization
      4. **Populate iteratively**: Use multiple tool calls to add specific items as needed
      5. **Adapt to user feedback**: Modify, add, or reorganize based on their input

      ## Examples of Natural Usage:

      - "Help me organize my move" → Create "Moving" with sub-lists like "Packing", "Utilities", "New Home Setup"
      - "I need a grocery list" → Create simple "Grocery List" and add items they mention
      - "Plan my vacation to Japan" → Create "Japan Trip" with sub-lists like "Tokyo", "Kyoto", "Osaka"
      - "Track my fitness goals" → Create "Fitness" with sub-lists like "Workouts", "Nutrition", "Progress"

      ## Context Awareness:
      - Current page: #{@context[:page] || 'unknown'}
      - Default to "personal" lists unless the context clearly indicates work/business
      - Use multiple tool calls as needed to fully organize the user's request
      - Be conversational and helpful - ask questions, make suggestions, iterate based on feedback

      The user controls the conversation. Follow their lead and help them organize whatever they want, however they want it structured.
    INSTRUCTIONS
  end
end
