# app/services/mcp_service.rb
class McpService
  include ActiveModel::Model
  include ActiveModel::Attributes

  attr_accessor :user, :context, :chat

  # Custom exceptions for better error handling
  class AuthorizationError < StandardError; end
  class ValidationError < StandardError; end
  class ConversationStateError < StandardError; end

  def initialize(user:, context: {}, chat: nil)
    @user = user
    @context = context
    @chat = chat || user.current_chat
    @tools = McpTools.new(user, context)
    @conversation_manager = ConversationStateManager.new(@chat)
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

    # Ensure conversation integrity BEFORE making API call
    begin
      @conversation_manager.ensure_conversation_integrity!
    rescue ConversationStateManager::ConversationError => e
      Rails.logger.warn "Conversation state warning (non-blocking): #{e.message}"
      # Don't block the conversation - just log the warning and continue
    rescue => e
      Rails.logger.error "Unexpected conversation error: #{e.message}"
      # Continue anyway - don't let validation block tool calls
    end

    begin
      # Use a transaction to ensure atomicity
      result = nil

      ActiveRecord::Base.transaction do
        # Set the model for this interaction if not already set
        model = Rails.application.config.mcp.model
        @chat.update!(model_id: model) if @chat.model_id.blank?

        # Add system instructions if context requires it
        if needs_system_instructions?
          @chat.with_instructions(build_system_instructions, replace: true)
        end

        # Configure tools if available
        if @tools.available_tools.any?
          @tools.available_tools.each do |tool|
            @chat.with_tool(tool)
          end
        end

        # Use RubyLLM's ask method which handles the full conversation flow
        begin
          response = @chat.ask(message_content)
        rescue PG::UniqueViolation => e
          if e.message.include?("list_id_and_position")
            retry_count = (@retry_count ||= 0) + 1
            if retry_count <= 2
              @retry_count = retry_count
              sleep(0.1)
              retry
            else
              raise StandardError, "Unable to add item due to position conflict after multiple retries"
            end
          else
            raise e
          end
        end

        # After successful processing, mark the conversation as stable
        @chat.update_column(:last_stable_at, Time.current)

        # Verify conversation state after the interaction
        begin
          @conversation_manager.validate_basic_structure! if @conversation_manager.respond_to?(:validate_basic_structure!)
        rescue => e
          Rails.logger.warn "Post-conversation validation warning: #{e.message}"
          # Don't fail the entire operation for validation issues
        end

        result = response.content
      end

      # Increment rate limit counters after successful processing
      rate_limiter.increment_counters!

      result

    rescue RubyLLM::BadRequestError => e
      handle_api_error(e, message_content)
    rescue RubyLLM::Error => e
      Rails.logger.error "RubyLLM Error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # If it's a conversation-related error, try with a fresh chat
      if conversation_related_error?(e)
        return retry_with_fresh_chat(message_content)
      end

      "I apologize, but I encountered an error processing your request. Please try again."
    rescue ConversationStateError => e
      Rails.logger.error "Conversation state error: #{e.message}"
      retry_with_fresh_chat(message_content)
    end

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

  def handle_api_error(error, message_content)
    Rails.logger.error "OpenAI API Error: #{error.message}"

    # Check if it's the specific tool/conversation error
    if error.message.include?("messages with role 'tool' must be a response to a preceeding message with 'tool_calls'")
      Rails.logger.warn "Detected tool conversation structure error, attempting recovery"
      return retry_with_fresh_chat(message_content)
    end

    # Check if it's an invalid parameter error related to conversation structure
    if error.message.include?("Invalid parameter") && error.message.include?("messages")
      Rails.logger.warn "Detected conversation parameter error, attempting recovery"
      return retry_with_fresh_chat(message_content)
    end

    "I apologize, but there was an issue with the conversation format. I've started a fresh conversation to resolve this."
  end

  def conversation_related_error?(error)
    error_patterns = [
      /tool.*must be.*response.*tool_calls/i,
      /invalid.*parameter.*messages/i,
      /malformed.*conversation/i,
      /tool_call.*missing/i
    ]

    error_patterns.any? { |pattern| error.message.match?(pattern) }
  end

  def should_create_fresh_chat?(error)
    # Create fresh chat for certain types of severe errors
    severe_error_patterns = [
      ConversationStateManager::OrphanedToolCallError,
      ConversationStateManager::MalformedToolResponseError
    ]

    severe_error_patterns.any? { |pattern| error.is_a?(pattern) }
  end

  def retry_with_fresh_chat(message_content)
    Rails.logger.info "Retrying with fresh chat for user #{@user.id}"

    # Archive the problematic chat
    @chat.update!(status: "archived", title: "#{@chat.title} (Archived - Conversation Error)")

    # Create a fresh chat
    @chat = create_fresh_chat!
    @conversation_manager = ConversationStateManager.new(@chat)

    # Retry the message processing with the fresh chat
    begin
      # Set the model
      model = Rails.application.config.mcp.model
      @chat.update!(model_id: model)

      # Add system instructions
      @chat.with_instructions(build_system_instructions, replace: true)

      # Configure tools
      if @tools.available_tools.any?
        @tools.available_tools.each do |tool|
          @chat.with_tool(tool)
        end
      end

      # Process the message
      begin
        response = @chat.ask(message_content)
      rescue PG::UniqueViolation => e
        if e.message.include?("list_id_and_position")
          retry_count = (@fresh_chat_retry_count ||= 0) + 1
          if retry_count <= 2
            @fresh_chat_retry_count = retry_count
            sleep(0.1)
            retry
          else
            raise StandardError, "Unable to add item due to position conflict even with fresh chat"
          end
        else
          raise e
        end
      end
      response.content

    rescue => e
      Rails.logger.error "Failed to process message even with fresh chat: #{e.message}"
      "I encountered a technical issue and had to start a fresh conversation. Please try your request again."
    end
  end

  def create_fresh_chat!
    @user.chats.create!(
      status: "active",
      title: "Chat #{Time.current.strftime('%m/%d %H:%M')}"
    )
  end

  def needs_system_instructions?
    # Only add instructions if we have meaningful context or this is a new conversation
    @context.present? || @chat.messages.where(role: "system").empty?
  end

  def build_system_instructions
    instructions = []

    instructions << "You are an AI assistant integrated with Listopia, a collaborative list management application."
    instructions << "You can help users manage their lists, create items, update tasks, and collaborate with others."

    # Enhanced planning context instructions
    instructions << <<~PLANNING
      IMPORTANT: Listopia is fundamentally a planning and organization tool. When users mention ANY of the following, you should immediately create a list with relevant items:

      🎯 PLANNING CONTEXTS (always create lists):
      - Vacation/Travel planning (flights, hotels, itinerary, packing)
      - Project management (tasks, milestones, deliverables)
      - Goal setting (objectives, steps, milestones)
      - Event planning (weddings, parties, meetings)
      - Shopping (grocery, retail, supplies)
      - Moving/Relocation (packing, utilities, address changes)
      - Job search (resume, applications, interviews)
      - Learning/Education (courses, materials, schedule)
      - Health/Fitness (workouts, diet, appointments)
      - Financial planning (budgets, savings, investments)
      - Home improvement (tasks, materials, contractors)
      - Business strategy (initiatives, analysis, execution)

      📋 AUTOMATIC LIST CREATION RULES:
      1. When user mentions planning ANYTHING, create a list immediately using create_planning_list
      2. Always include a descriptive title and helpful description
      3. Auto-generate relevant planning items based on the context
      4. Use appropriate item types (task, goal, milestone, reminder)
      5. Set reasonable priorities (high for critical items, medium for important, low for nice-to-have)

      💡 EXAMPLES:
      - "Plan vacation to Argentina" → Create "Argentina Vacation Planning" list with flights, hotels, itinerary items
      - "Organize sprint for Q1" → Create "Q1 Sprint Planning" list with scope, tasks, milestones
      - "Need to quit smoking" → Create "Quit Smoking Plan" list with strategy steps, milestones, support items
      - "Planning wedding" → Create "Wedding Planning" list with venue, catering, invitations, etc.

      🚀 PROACTIVE PLANNING:
      - Don't wait for the user to say "create a list"
      - Recognize planning intent and act immediately
      - Suggest additional items that might be helpful
      - Ask follow-up questions to enhance the plan
    PLANNING

    if @context.present?
      instructions << "Current context: #{build_context_message}"
    end

    if @tools.available_tools.any?
      instructions << "You have access to tools that can help you:"
      @tools.available_tools.each do |tool|
        instructions << "- #{tool.class.name}: #{tool.class.description}"
      end
      instructions << "Use these tools proactively when appropriate to help the user accomplish their goals."
    end

    instructions << "Always be helpful, accurate, and respect user permissions."
    instructions << "Remember: When in doubt about whether something involves planning, CREATE A LIST!"

    instructions.join("\n\n")
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
end
