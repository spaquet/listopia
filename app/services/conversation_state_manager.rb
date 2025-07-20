# app/services/conversation_state_manager.rb
class ConversationStateManager
  class ConversationError < StandardError; end
  class OrphanedToolCallError < ConversationError; end
  class MalformedToolResponseError < ConversationError; end

  def initialize(chat)
    @chat = chat
    @logger = Rails.logger
  end

  # Main method to ensure conversation integrity before sending to OpenAI
  def ensure_conversation_integrity!
    # During active conversations (less than 5 minutes ago), only do minimal validation
    # This prevents interference with ongoing tool calls
    if @chat.messages.where(role: "user").where("created_at > ?", 5.minutes.ago).exists?
      Rails.logger.debug "Active conversation detected, skipping aggressive validation"
      validate_basic_structure!
    else
      Rails.logger.debug "Inactive conversation, performing full validation"
      # Inactive conversation - full cleanup
      validate_conversation_structure!
      cleanup_orphaned_messages!
      # Skip tool call response pairing validation during normal operations
      # validate_tool_call_response_pairing!
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

  private

  def validate_basic_structure!
    # Only check for obvious structural issues, don't remove messages or raise errors
    recent_messages = @chat.messages.where("created_at > ?", 5.minutes.ago).order(:created_at)

    recent_messages.each do |msg|
      if msg.role == "tool" && msg.tool_call_id.blank?
        @logger.warn "Tool message #{msg.id} missing tool_call_id (non-critical during active conversation)"
      end
    end

    # Always return true during active conversations to prevent blocking
    true
  end

  def validate_conversation_structure!
    messages = @chat.messages.order(:created_at)

    messages.each_cons(2) do |prev_msg, curr_msg|
      # Check for tool response without preceding tool call
      if curr_msg.role == "tool" && prev_msg.role != "assistant"
        raise MalformedToolResponseError, "Tool response message #{curr_msg.id} follows #{prev_msg.role} instead of assistant"
      end

      # Check for tool response without tool_call_id
      if curr_msg.role == "tool" && curr_msg.tool_call_id.blank?
        raise MalformedToolResponseError, "Tool response message #{curr_msg.id} missing tool_call_id"
      end
    end
  end

  def cleanup_orphaned_messages!
    # Find orphaned tool responses (tool messages without corresponding tool calls)
    orphaned_tool_messages = @chat.messages.where(role: "tool").select do |tool_msg|
      !has_corresponding_tool_call?(tool_msg)
    end

    if orphaned_tool_messages.any?
      @logger.warn "Removing #{orphaned_tool_messages.count} orphaned tool messages from chat #{@chat.id}"
      orphaned_tool_messages.each(&:destroy!)
    end

    # Find orphaned assistant messages with tool calls but no responses
    orphaned_assistant_messages = @chat.messages.where(role: "assistant").includes(:tool_calls).select do |assistant_msg|
      assistant_msg.tool_calls.any? && !has_tool_responses_for_message?(assistant_msg)
    end

    if orphaned_assistant_messages.any?
      @logger.warn "Found #{orphaned_assistant_messages.count} assistant messages with tool calls but no responses"
      # Don't auto-delete these, but log them for investigation
    end
  end

  def validate_tool_call_response_pairing!
    assistant_messages_with_tools = @chat.messages.where(role: "assistant").includes(:tool_calls)
                                         .where.not(id: @chat.tool_calls.select(:message_id).where(tool_calls: { id: nil }))

    assistant_messages_with_tools.each do |assistant_msg|
      assistant_msg.tool_calls.each do |tool_call|
        tool_response = find_tool_response(tool_call.tool_call_id)

        if tool_response.nil?
          raise OrphanedToolCallError, "Tool call #{tool_call.tool_call_id} has no corresponding response"
        end

        # Ensure the tool response immediately follows the assistant message
        next_message = @chat.messages.where("created_at > ?", assistant_msg.created_at)
                            .order(:created_at).first

        if next_message != tool_response
          @logger.warn "Tool response #{tool_response.id} doesn't immediately follow tool call #{tool_call.tool_call_id}"
        end
      end
    end
  end

  def attempt_conversation_repair!
    @logger.info "Attempting to repair conversation for chat #{@chat.id}"

    # Strategy 1: Remove orphaned tool messages
    cleanup_orphaned_messages!

    # Strategy 2: If conversation is severely broken, truncate to last known good state
    last_user_message = @chat.messages.where(role: "user").order(:created_at).last
    if last_user_message
      # Remove any messages created after the last user message that aren't properly paired
      potentially_broken_messages = @chat.messages.where("created_at > ?", last_user_message.created_at)
                                         .order(:created_at)

      # Keep only properly structured tool call/response pairs
      messages_to_keep = []
      i = 0
      while i < potentially_broken_messages.length
        msg = potentially_broken_messages[i]

        if msg.role == "assistant" && msg.tool_calls.any?
          # Check if the next message(s) are proper tool responses
          tool_call_ids = msg.tool_calls.pluck(:tool_call_id)
          next_messages = potentially_broken_messages[(i+1)..(i+tool_call_ids.length)]

          if next_messages&.all? { |m| m.role == "tool" && tool_call_ids.include?(m.tool_call_id) }
            # This is a proper tool call/response sequence
            messages_to_keep << msg
            messages_to_keep.concat(next_messages)
            i += tool_call_ids.length + 1
          else
            # Broken sequence, stop here
            break
          end
        elsif msg.role == "assistant" && msg.tool_calls.empty?
          # Regular assistant message, keep it
          messages_to_keep << msg
          i += 1
        else
          # Unexpected message in this position, stop here
          break
        end
      end

      # Remove messages that aren't in the keep list
      messages_to_remove = potentially_broken_messages - messages_to_keep
      if messages_to_remove.any?
        @logger.warn "Removing #{messages_to_remove.count} messages to repair conversation"
        messages_to_remove.each(&:destroy!)
      end
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
        matching_tool_call = prev_msg[:tool_calls]&.find { |tc| tc[:id] == tool_call_id }

        unless matching_tool_call
          raise MalformedToolResponseError, "Tool message at index #{index} has unmatched tool_call_id: #{tool_call_id}"
        end
      end
    end
  end

  def has_corresponding_tool_call?(tool_message)
    return false if tool_message.tool_call_id.blank?

    @chat.tool_calls.exists?(tool_call_id: tool_message.tool_call_id)
  end

  def has_tool_responses_for_message?(assistant_message)
    tool_call_ids = assistant_message.tool_calls.pluck(:tool_call_id)
    return true if tool_call_ids.empty?

    tool_call_ids.all? do |tool_call_id|
      @chat.messages.exists?(role: "tool", tool_call_id: tool_call_id)
    end
  end

  def find_tool_response(tool_call_id)
    @chat.messages.find_by(role: "tool", tool_call_id: tool_call_id)
  end
end
