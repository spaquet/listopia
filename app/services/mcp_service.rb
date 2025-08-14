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

    # Initialize context manager
    @context_manager = ConversationContextManager.new(
      user: @user,
      chat: @chat,
      current_context: @context
    )

    # Add enhanced services only if error recovery is enabled AND chat exists
    if Rails.application.config.mcp.error_recovery&.enabled && @chat
      begin
        @chat_state_manager = ChatStateManager.new(@chat)
        @resilient_llm = ResilientRubyLlmService.new
        @error_recovery = ErrorRecoveryService.new(user: @user, chat: @chat, context: @context)
      rescue => e
        Rails.logger.error "Failed to initialize enhanced error recovery services: #{e.message}"
        # Fall back to basic services
        @chat_state_manager = nil
        @resilient_llm = nil
        @error_recovery = nil
      end
    end

    # Add AI orchestration services for Phase 3
    if Rails.application.config.mcp.ai_orchestration&.enabled && @chat
      begin
        @ai_orchestrator = AiOrchestrationService.new(user: @user, context: @context, chat: @chat)
      rescue => e
        Rails.logger.error "Failed to initialize AI orchestration: #{e.message}"
        @ai_orchestrator = nil
      end
    end
  end

  def process_message(message_content)
    start_time = Time.current

    # Ensure user is authenticated
    raise AuthorizationError, "User must be authenticated" unless @user

    # Check rate limits using existing rate limiter
    rate_limiter = McpRateLimiter.new(@user)
    rate_limiter.check_rate_limit!

    # Validate message length using existing config
    if message_content.length > Rails.application.config.mcp.max_message_length
      raise ValidationError, "Message is too long (max #{Rails.application.config.mcp.max_message_length} characters)"
    end

    begin
      # Resolve context references before processing
      resolved_context = @context_manager.resolve_references(message_content)
      enhanced_context = @context.merge(resolved_context)
      @enhanced_context = enhanced_context

      # Update tools with enhanced context
      @tools = McpTools.new(@user, enhanced_context)

      # Enhanced error recovery if enabled
      if @chat_state_manager && Rails.application.config.mcp.state_management&.auto_checkpoint
        # Create checkpoint before processing
        checkpoint_name = @chat_state_manager.create_checkpoint!("pre_message_#{Time.current.to_i}")

        # Validate and heal state proactively
        health_result = @chat_state_manager.validate_and_heal_state!

        case health_result[:status]
        when :recovery_branch_created
          # Switch to recovery branch if needed
          @chat = health_result[:recovery_chat]
          @chat_state_manager = ChatStateManager.new(@chat)
          @error_recovery = ErrorRecoveryService.new(user: @user, chat: @chat, context: @context)
        end
      else
        # Fallback to existing conversation integrity check
        begin
          @conversation_manager.ensure_conversation_integrity!
        rescue ConversationStateManager::ConversationError => e
          Rails.logger.warn "Conversation state warning (non-blocking): #{e.message}"
        rescue => e
          Rails.logger.error "Unexpected conversation error: #{e.message}"
        end
      end

      # NEW: Enhanced processing with AI orchestration
      result = if @ai_orchestrator && should_use_orchestration?(message_content)
        process_with_ai_orchestration(message_content)
      elsif @resilient_llm
        process_with_resilient_llm(message_content, enhanced_context)
      else
        process_with_standard_llm(message_content)
      end

      # Track the chat interaction
      @context_manager.track_action(
        action: "chat_message_sent",
        entity: @chat,
        metadata: {
          message_length: message_content.length,
          resolved_context: resolved_context.keys,
          processing_time: Time.current - start_time
        }
      )

      # Mark successful processing
      @chat.update_columns(
        last_stable_at: Time.current,
        conversation_state: "stable"
      )

      # Increment rate limit counters after successful processing
      rate_limiter.increment_counters!

      result.respond_to?(:content) ? result.content : result

    rescue McpRateLimiter::RateLimitError => e
      e.message
    rescue ValidationError => e
      e.message
    rescue => e
      Rails.logger.error "MCP Error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Use error recovery service if available
      if @error_recovery
        recovery_result = @error_recovery.recover_from_error(e, original_message: message_content)

        if recovery_result[:recoverable] && recovery_result[:new_chat]
          # Switch to new chat and retry
          @chat = recovery_result[:new_chat]
          process_message(message_content)
        elsif recovery_result[:recoverable] && recovery_result[:retry_message]
          # Retry with same chat after healing
          process_message(recovery_result[:retry_message])
        else
          # Return user-friendly error message
          recovery_result[:user_message] || "I apologize, but I encountered an error processing your request. Please try again."
        end
      else
        # Fallback to existing error handling
        handle_standard_error(e, message_content)
      end
    end
  end

private

# NEW: Determine if message would benefit from AI orchestration
def should_use_orchestration?(message_content)
  orchestration_keywords = [
    "plan", "planning", "create a plan", "step by step", "workflow",
    "organize", "break down", "manage", "strategy", "approach",
    "help me with", "guide me", "walk me through", "create a list for",
    "project", "event", "travel", "learning", "curriculum", "schedule"
  ]

  message_lower = message_content.downcase
  orchestration_keywords.any? { |keyword| message_lower.include?(keyword) }
end

# NEW: Process message using AI orchestration
def process_with_ai_orchestration(message_content)
  orchestration_result = @ai_orchestrator.orchestrate_task(message_content)

  if orchestration_result[:success]
    orchestration_result[:result]
  elsif orchestration_result[:fallback_needed]
    # Fallback to standard processing
    if @resilient_llm
      process_with_resilient_llm(message_content)
    else
      process_with_standard_llm(message_content)
    end
  else
    orchestration_result[:user_message] || "I encountered an issue processing your request. Please try again."
  end
end

  private

  def should_use_orchestration?(message_content)
    # Determine if message would benefit from AI orchestration
    orchestration_keywords = [
      "plan", "planning", "create a plan", "step by step", "workflow",
      "organize", "break down", "manage", "strategy", "approach"
    ]

    message_lower = message_content.downcase
    orchestration_keywords.any? { |keyword| message_lower.include?(keyword) }
  end

  def process_with_ai_orchestration(message_content)
    orchestration_result = @ai_orchestrator.orchestrate_task(message_content)

    if orchestration_result[:success]
      orchestration_result[:result]
    elsif orchestration_result[:fallback_needed]
      # Fallback to standard processing
      if @resilient_llm
        process_with_resilient_llm(message_content)
      else
        process_with_standard_llm(message_content)
      end
    else
      orchestration_result[:user_message] || "I encountered an issue processing your request. Please try again."
    end
  end

  def process_with_resilient_llm(message_content, enhanced_context = nil)
    context_to_use = enhanced_context || @context

    # Set the model using existing config
    model = Rails.application.config.mcp.model
    @chat.update!(model_id: model) if @chat.model_id.blank?

    # Add system instructions with context awareness
    if needs_system_instructions?
      @chat.with_instructions(build_system_instructions, replace: true)
    end

    # Configure tools with enhanced context
    if @tools.available_tools.any?
      @tools.available_tools.each do |tool|
        @chat.with_tool(tool)
      end
    end

    # Process the message with enhanced error handling
    begin
      response = @resilient_llm.ask_with_retry(@chat, message_content,
        context: context_to_use,
        timeout: Rails.application.config.mcp.request_timeout
      )
    rescue => e
      Rails.logger.error "Enhanced LLM processing failed: #{e.message}"

      # Track the error context
      @context_manager.track_action(
        action: "chat_error",
        entity: @chat,
        metadata: {
          error_type: e.class.name,
          error_message: e.message,
          context_size: context_to_use.keys.size
        }
      )

      raise e
    end

    response.content
  end

  def process_with_standard_llm(message_content)
    # Eager loading for tool_calls
    messages = @chat.messages.includes(:tool_calls).ordered

    # Your existing process_message logic from the transaction block
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

    result
  end

  def handle_standard_error(error, message_content)
    # Your existing error handling logic as fallback
    case error
    when RubyLLM::BadRequestError
      handle_api_error(error, message_content)
    when RubyLLM::Error
      Rails.logger.error "RubyLLM Error: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")

      # If it's a conversation-related error, try with a fresh chat
      if conversation_related_error?(error)
        return retry_with_fresh_chat(message_content)
      end

      "I apologize, but I encountered an error processing your request. Please try again."
    when ConversationStateError
      Rails.logger.error "Conversation state error: #{error.message}"
      retry_with_fresh_chat(message_content)
    else
      Rails.logger.error "MCP Error: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")

      "I apologize, but I encountered an error processing your request. Please try again."
    end
  end

  def handle_api_error(error, message_content)
    Rails.logger.error "OpenAI API Error: #{error.message}"

    # Check for the specific tool call mismatch error
    if error.message.include?("tool_calls") && error.message.include?("must be followed by tool messages")
      Rails.logger.warn "Detected tool call/response mismatch error, attempting recovery"
      return retry_with_fresh_chat(message_content)
    end

    # Check for invalid parameter errors related to conversation structure
    if error.message.include?("Invalid parameter") && error.message.include?("messages")
      Rails.logger.warn "Detected conversation parameter error, attempting recovery"
      return retry_with_fresh_chat(message_content)
    end

    # Check for other conversation structure issues
    if conversation_related_error?(error)
      return retry_with_fresh_chat(message_content)
    end

    "I apologize, but there was an issue with the conversation format. I've started a fresh conversation to resolve this."
  end

  def conversation_related_error?(error)
    error_patterns = [
      /tool.*must be.*response.*tool_calls/i,
      /tool_call_id.*did not have response messages/i,
      /invalid.*parameter.*messages/i,
      /malformed.*conversation/i,
      /tool_call.*missing/i,
      /assistant message.*tool_calls.*must be followed/i
    ]

    error_patterns.any? { |pattern| error.message.match?(pattern) }
  end


  def conversation_related_error?(error)
    error_patterns = [
      /tool.*must be.*response.*tool_calls/i,
      /tool_call_id.*did not have response messages/i,
      /invalid.*parameter.*messages/i,
      /malformed.*conversation/i,
      /tool_call.*missing/i,
      /assistant message.*tool_calls.*must be followed/i
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
    original_title = @chat.title
    @chat.update!(
      status: "archived",
      title: "#{original_title} (Archived - Conversation Error at #{Time.current.strftime('%H:%M')})"
    )

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

    # Use the enhanced context if available
    if @enhanced_context && @context_manager
      context_instructions = @context_manager.get_ai_context_instructions
      if context_instructions.present?
        instructions << "\nCURRENT CONTEXT:"
        instructions << context_instructions
        instructions << "\nWhen the user refers to 'this list', 'these items', 'first 3 items', etc., use the context above to resolve these references."
      end
    end

    # Enhanced planning context instructions
    instructions << <<~PLANNING
      IMPORTANT: Listopia is fundamentally a planning and organization tool.
      When users ask for help with planning, organizing, or managing tasks:
      1. CREATE concrete, actionable lists using the available tools
      2. ORGANIZE information into clear, structured formats
      3. SUGGEST workflows and processes that help users stay organized
      4. USE the list and item management tools to create tangible outcomes

      Available tools can help you:
      - Create and manage lists for any planning purpose
      - Add, update, and organize list items
      - Set priorities, due dates, and assignments
      - Create structured approaches to complex projects

      Always aim to provide practical, organized solutions that users can immediately act upon.
    PLANNING

    # Keep your existing context logic
    if @context.present?
      if @context["page"]
        instructions << "Current page context: #{@context['page']}"
      end

      if @context["selected_items"]
        instructions << "User has selected items: #{@context['selected_items'].join(', ')}"
      end
    end

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
