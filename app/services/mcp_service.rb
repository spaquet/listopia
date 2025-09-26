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
    # RubyLLM 1.8 handles all errors automatically
  end

  private

  def setup_chat
    @chat.with_instructions(build_system_instructions)
    @chat.with_tool(ListManagementTool.new(@user, @context))
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
