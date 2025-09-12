# app/services/tool_response_manager.rb
class ToolResponseManager
  class ToolCallError < StandardError; end
  class MissingToolCallError < ToolCallError; end
  class InvalidToolCallIdError < ToolCallError; end

  def initialize(chat)
    @chat = chat
    @logger = Rails.logger
  end

  # Create a tool response message safely with proper validation
  def create_tool_response(tool_call_id:, content:, metadata: {})
    Rails.logger.debug "Creating tool response for tool_call_id: #{tool_call_id}"

    # Validate tool_call_id format
    validate_tool_call_id_format!(tool_call_id)

    # Find the corresponding tool call
    tool_call = find_tool_call!(tool_call_id)

    # Create the response message with proper linking
    response_message = Message.create!(
      chat: @chat,
      role: "tool",
      tool_call_id: tool_call_id,
      content: content.to_s,
      message_type: "tool_result",
      metadata: build_tool_response_metadata(tool_call, metadata)
    )

    Rails.logger.info "Created tool response message #{response_message.id} for tool call #{tool_call_id}"
    response_message

  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to create tool response: #{e.message}"
    raise ToolCallError, "Failed to create tool response: #{e.message}"
  rescue => e
    Rails.logger.error "Unexpected error creating tool response: #{e.message}"
    raise ToolCallError, "Unexpected error creating tool response: #{e.message}"
  end

  # Create multiple tool responses in a transaction
  def create_tool_responses(responses)
    ActiveRecord::Base.transaction do
      responses.map do |response_data|
        create_tool_response(
          tool_call_id: response_data[:tool_call_id],
          content: response_data[:content],
          metadata: response_data[:metadata] || {}
        )
      end
    end
  end

  # Validate that all tool calls for a message have responses
  def validate_tool_call_completeness(assistant_message)
    missing_responses = []

    assistant_message.tool_calls.each do |tool_call|
      unless @chat.messages.exists?(role: "tool", tool_call_id: tool_call.tool_call_id)
        missing_responses << tool_call.tool_call_id
      end
    end

    if missing_responses.any?
      raise MissingToolCallError, "Missing tool responses for: #{missing_responses.join(', ')}"
    end

    true
  end

  # Check if a tool call already has a response
  def tool_call_has_response?(tool_call_id)
    @chat.messages.exists?(role: "tool", tool_call_id: tool_call_id)
  end

  # Get all pending tool calls (those without responses)
  def pending_tool_calls
    tool_call_ids_with_responses = @chat.messages.where(role: "tool")
                                       .where.not(tool_call_id: [ nil, "" ])
                                       .pluck(:tool_call_id)

    @chat.tool_calls.where.not(tool_call_id: tool_call_ids_with_responses)
  end

  # Clean up orphaned tool calls and responses
  def cleanup_orphaned_tool_data
    cleanup_count = 0

    # Remove tool responses without corresponding tool calls
    orphaned_responses = @chat.messages.where(role: "tool")
                             .where.not(tool_call_id: [ nil, "" ])
                             .select do |msg|
      !@chat.tool_calls.exists?(tool_call_id: msg.tool_call_id)
    end

    if orphaned_responses.any?
      Rails.logger.warn "Removing #{orphaned_responses.count} orphaned tool responses"
      cleanup_count += orphaned_responses.count
      orphaned_responses.each(&:destroy!)
    end

    # Remove tool calls without corresponding assistant messages
    orphaned_calls = @chat.tool_calls.includes(:message)
                         .select { |tc| tc.message.nil? || tc.message.role != "assistant" }

    if orphaned_calls.any?
      Rails.logger.warn "Removing #{orphaned_calls.count} orphaned tool calls"
      cleanup_count += orphaned_calls.count
      orphaned_calls.each(&:destroy!)
    end

    cleanup_count
  end

  private

  def validate_tool_call_id_format!(tool_call_id)
    if tool_call_id.blank?
      raise InvalidToolCallIdError, "Tool call ID cannot be blank"
    end

    unless tool_call_id.is_a?(String)
      raise InvalidToolCallIdError, "Tool call ID must be a string"
    end

    unless tool_call_id.start_with?("call_")
      raise InvalidToolCallIdError, "Tool call ID must start with 'call_' for OpenAI compatibility"
    end

    if tool_call_id.length < 10
      raise InvalidToolCallIdError, "Tool call ID appears to be too short: #{tool_call_id}"
    end
  end

  def find_tool_call!(tool_call_id)
    tool_call = @chat.tool_calls.find_by(tool_call_id: tool_call_id)

    unless tool_call
      available_ids = @chat.tool_calls.pluck(:tool_call_id)
      raise MissingToolCallError,
            "No tool call found with ID: #{tool_call_id}. Available IDs: #{available_ids.join(', ')}"
    end

    tool_call
  end

  def build_tool_response_metadata(tool_call, additional_metadata)
    {
      tool_name: tool_call.name,
      tool_call_created_at: tool_call.created_at,
      tool_arguments: tool_call.arguments,
      response_created_at: Time.current,
      chat_id: @chat.id
    }.merge(additional_metadata)
  end
end
