# app/services/conversation_state_manager.rb
class ConversationStateManager
  class ConversationError < StandardError; end
  class OrphanedToolCallError < ConversationError; end
  class MalformedToolResponseError < ConversationError; end
  class InvalidToolCallIdError < ConversationError; end

  def initialize(chat)
    @chat = chat
    @logger = Rails.logger
  end

  # Main method to ensure conversation integrity before sending to OpenAI
  def ensure_conversation_integrity!
    # During active conversations (less than 5 minutes ago), only do basic validation
    if recently_active?
      Rails.logger.debug "Active conversation detected, performing minimal validation"
      validate_basic_structure!
    else
      Rails.logger.debug "Inactive conversation, performing comprehensive cleanup"
      perform_comprehensive_cleanup!
    end
  end

  # Get a clean conversation history safe for OpenAI API
  def clean_conversation_history
    ensure_conversation_integrity!

    messages = @chat.messages.includes(:tool_calls)
                    .order(:created_at)
                    .map { |msg| build_openai_message(msg) }
                    .compact

    # Final validation that the conversation follows OpenAI's rules
    validate_openai_message_format!(messages)

    messages
  end

  # Aggressively clean up conversation state
  def perform_comprehensive_cleanup!
    Rails.logger.info "Performing comprehensive cleanup for chat #{@chat.id}"

    cleanup_count = 0

    # Step 1: Remove tool messages without tool_call_id
    orphaned_tool_messages = @chat.messages.where(role: "tool", tool_call_id: [ nil, "" ])
    if orphaned_tool_messages.any?
      Rails.logger.warn "Removing #{orphaned_tool_messages.count} tool messages without tool_call_id"
      cleanup_count += orphaned_tool_messages.count
      orphaned_tool_messages.destroy_all
    end

    # Step 2: Remove tool messages with invalid tool_call_id format
    invalid_format_messages = @chat.messages.where(role: "tool")
                                           .where.not(tool_call_id: [ nil, "" ])
                                           .where.not("tool_call_id LIKE 'call_%'")
    if invalid_format_messages.any?
      Rails.logger.warn "Removing #{invalid_format_messages.count} tool messages with invalid tool_call_id format"
      cleanup_count += invalid_format_messages.count
      invalid_format_messages.destroy_all
    end

    # Step 3: Remove tool messages that don't have corresponding tool calls
    remaining_tool_messages = @chat.messages.where(role: "tool").includes(:chat)
    orphaned_responses = remaining_tool_messages.select do |msg|
      !@chat.tool_calls.exists?(tool_call_id: msg.tool_call_id)
    end

    if orphaned_responses.any?
      Rails.logger.warn "Removing #{orphaned_responses.count} tool messages without corresponding tool calls"
      cleanup_count += orphaned_responses.count
      orphaned_responses.each(&:destroy!)
    end

    # Step 4: Remove assistant messages with tool calls that have no responses
    assistant_with_orphaned_calls = @chat.messages.where(role: "assistant")
                                         .includes(:tool_calls)
                                         .select { |msg| has_orphaned_tool_calls?(msg) }

    if assistant_with_orphaned_calls.any?
      Rails.logger.warn "Removing #{assistant_with_orphaned_calls.count} assistant messages with orphaned tool calls"
      cleanup_count += assistant_with_orphaned_calls.count
      assistant_with_orphaned_calls.each(&:destroy!)
    end

    # Step 5: Validate conversation flow and fix any remaining issues
    validate_conversation_flow!

    # Update cleanup tracking
    if cleanup_count > 0
      @chat.update_columns(
        last_cleanup_at: Time.current,
        conversation_state: "stable",
        last_stable_at: Time.current
      )
      Rails.logger.info "Cleaned up #{cleanup_count} problematic messages from chat #{@chat.id}"
    end

    cleanup_count
  end

  private

  def recently_active?
    @chat.messages.where(role: "user").where("created_at > ?", 5.minutes.ago).exists?
  end

  def validate_basic_structure!
    # Only check for obvious structural issues without removing messages
    recent_messages = @chat.messages.where("created_at > ?", 5.minutes.ago).order(:created_at)

    recent_messages.each do |msg|
      if msg.role == "tool" && msg.tool_call_id.blank?
        @logger.warn "Tool message #{msg.id} missing tool_call_id (flagged for cleanup)"
        @chat.update_column(:conversation_state, "needs_cleanup")
      end
    end
  end

  def validate_conversation_flow!
    messages = @chat.messages.order(:created_at)
    prev_msg = nil

    messages.each do |curr_msg|
      if curr_msg.role == "tool"
        # Tool messages must follow assistant messages with tool calls
        unless prev_msg && prev_msg.role == "assistant" && prev_msg.tool_calls.any?
          raise MalformedToolResponseError, "Tool message #{curr_msg.id} not properly preceded by assistant with tool calls"
        end

        # Tool message must have valid tool_call_id
        if curr_msg.tool_call_id.blank?
          raise InvalidToolCallIdError, "Tool message #{curr_msg.id} missing tool_call_id"
        end

        # Validate tool_call_id format
        unless curr_msg.tool_call_id.start_with?("call_")
          raise InvalidToolCallIdError, "Tool message #{curr_msg.id} has invalid tool_call_id format: #{curr_msg.tool_call_id}"
        end

        # Ensure corresponding tool call exists
        unless prev_msg.tool_calls.exists?(tool_call_id: curr_msg.tool_call_id)
          raise OrphanedToolCallError, "Tool message #{curr_msg.id} references non-existent tool call: #{curr_msg.tool_call_id}"
        end
      end

      prev_msg = curr_msg
    end
  end

  def build_openai_message(message)
    case message.role
    when "user", "system"
      {
        role: message.role,
        content: message.content || ""
      }
    when "assistant"
      msg = {
        role: "assistant",
        content: message.content || ""
      }

      if message.tool_calls.any?
        msg[:tool_calls] = message.tool_calls.map do |tool_call|
          {
            id: tool_call.tool_call_id,
            type: "function",
            function: {
              name: tool_call.name,
              arguments: tool_call.arguments.to_json
            }
          }
        end
      end

      msg
    when "tool"
      if message.tool_call_id.present?
        {
          role: "tool",
          tool_call_id: message.tool_call_id,
          content: message.content || ""
        }
      else
        @logger.error "Tool message #{message.id} missing tool_call_id, skipping"
        nil
      end
    else
      @logger.error "Unknown message role: #{message.role}"
      nil
    end
  end

  def validate_openai_message_format!(messages)
    messages.each_with_index do |msg, index|
      if msg[:role] == "tool"
        # Tool messages must be preceded by assistant message with tool_calls
        prev_msg = messages[index - 1]

        unless prev_msg && prev_msg[:role] == "assistant" && prev_msg[:tool_calls]&.any?
          raise MalformedToolResponseError, "Tool message at index #{index} not preceded by assistant with tool_calls"
        end

        # Tool message must have valid tool_call_id that matches a previous tool call
        tool_call_id = msg[:tool_call_id]
        unless tool_call_id.present?
          raise InvalidToolCallIdError, "Tool message at index #{index} missing tool_call_id"
        end

        matching_tool_call = prev_msg[:tool_calls]&.find { |tc| tc[:id] == tool_call_id }
        unless matching_tool_call
          raise MalformedToolResponseError, "Tool message at index #{index} has unmatched tool_call_id: #{tool_call_id}"
        end
      end
    end
  end

  def has_orphaned_tool_calls?(assistant_message)
    return false unless assistant_message.tool_calls.any?

    assistant_message.tool_calls.any? do |tool_call|
      !@chat.messages.exists?(role: "tool", tool_call_id: tool_call.tool_call_id)
    end
  end
end
