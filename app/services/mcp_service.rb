# app/services/mcp_service.rb
class McpService
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
    max_length = Rails.application.config.mcp&.max_message_length || 2000
    if message_content.length > max_length
      raise ValidationError, "Message is too long (max #{max_length} characters)"
    end

    # Save user message to database
    user_message = @chat.add_user_message(message_content, context: @context)

    # Use RubyLLM with correct syntax - create a chat instance first
    chat = RubyLLM.chat(
      model: Rails.application.config.mcp&.model || "gpt-4-turbo-preview"
    )

    # Ask the question and get response
    response = chat.ask(message_content)
    response_content = response.content

    # Save assistant message to database
    processing_time = Time.current - start_time
    @chat.add_assistant_message(
      response_content,
      tool_calls: [],
      tool_results: [],
      metadata: {
        llm_provider: "openai",
        llm_model: Rails.application.config.mcp&.model || "gpt-4-turbo-preview",
        processing_time: processing_time,
        context_snapshot: @context
      }
    )

    # Increment rate limit counters after successful processing
    rate_limiter.increment_counters!

    # Return the response content
    response_content

  rescue McpRateLimiter::RateLimitError => e
    e.message
  rescue ValidationError => e
    e.message
  rescue => e
    Rails.logger.error "MCP Error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    "I apologize, but I encountered an error processing your request. Please try again."
  end

  private

  def build_conversation_history
    messages = [
      { role: "system", content: build_system_prompt }
    ]

    # Add recent messages from chat history
    recent_messages = @chat.latest_messages(10)
    messages += recent_messages.map(&:to_llm_format)

    # Add current user message with context
    messages << {
      role: "user",
      content: "Current context: #{build_context_message}"
    }

    messages
  end

  def build_system_prompt
    prompt = <<~PROMPT
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

      Current context: #{build_context_message}

      Respond naturally and conversationally. Use the provided tools to perform actions when requested.
    PROMPT

    prompt
  end

  def build_context_message
    return "No additional context available." if @context.blank?

    context_parts = []

    if @context["page"]
      context_parts << "User is currently on page: #{@context['page']}"
    end

    if @context["list_id"]
      context_parts << "User is viewing list: #{@context['list_title']} (ID: #{@context['list_id']})"
      context_parts << "List has #{@context['items_count']} items, #{@context['completed_count']} completed"
      context_parts << "User #{@context['is_owner'] ? 'owns' : 'collaborates on'} this list"
      context_parts << "User #{@context['can_collaborate'] ? 'can edit' : 'can only view'} this list"
    end

    if @context["total_lists"]
      context_parts << "User has access to #{@context['total_lists']} total lists"
    end

    context_parts.join(". ")
  end

  def process_tool_calls(llm_response)
    tool_calls = extract_tool_calls(llm_response)
    return [] unless tool_calls.any?

    tool_calls.map do |tool_call|
      begin
        function_name = tool_call["function"]["name"]
        arguments = JSON.parse(tool_call["function"]["arguments"])

        # Execute the tool
        result = @tools.call_tool(function_name, arguments)

        {
          tool_call_id: tool_call["id"],
          function_name: function_name,
          arguments: arguments,
          result: result,
          success: true
        }
      rescue => e
        Rails.logger.error "Tool call error: #{e.message}"
        {
          tool_call_id: tool_call["id"],
          function_name: function_name,
          arguments: arguments,
          result: { error: e.message },
          success: false
        }
      end
    end
  end

  def extract_tool_calls(llm_response)
    llm_response.dig("choices", 0, "message", "tool_calls") || []
  end

  def extract_response_content(llm_response)
    content = llm_response.dig("choices", 0, "message", "content")

    # If no content but there were tool calls, provide a default response
    if content.blank? && extract_tool_calls(llm_response).any?
      "I've processed your request. Please check for any updates."
    else
      content || "I've received your message and processed it."
    end
  end

  class AuthorizationError < StandardError; end
  class ValidationError < StandardError; end
end
