# app/services/chat_state_manager.rb
class ChatStateManager
  include ActiveModel::Model
  include ActiveModel::Attributes

  # Custom exceptions for state management
  class StateCorruptionError < StandardError; end
  class CheckpointError < StandardError; end
  class ConversationBranchError < StandardError; end
  class StateValidationError < StandardError; end

  attr_accessor :chat, :conversation_manager

  def initialize(chat)
    @chat = chat
    @conversation_manager = ConversationStateManager.new(chat)
    @logger = Rails.logger
  end

  # Create a conversation checkpoint for recovery purposes (using database instead of Redis)
  def create_checkpoint!(checkpoint_name = nil)
    checkpoint_name ||= "checkpoint_#{Time.current.to_i}"

    begin
      # Validate current state before checkpoint
      validate_conversation_state!

      # Store checkpoint in database instead of Redis
      checkpoint = ConversationCheckpoint.create!(
        chat: @chat,
        checkpoint_name: checkpoint_name,
        message_count: @chat.messages.count,
        tool_calls_count: @chat.tool_calls.count,
        conversation_state: @chat.conversation_state,
        messages_snapshot: serialize_messages_for_checkpoint,
        context_data: extract_context_data
      )

      @logger.info "Created checkpoint '#{checkpoint_name}' for chat #{@chat.id}"
      checkpoint_name

    rescue => e
      @logger.error "Failed to create checkpoint for chat #{@chat.id}: #{e.message}"
      raise CheckpointError, "Failed to create conversation checkpoint: #{e.message}"
    end
  end

  # Restore conversation from a checkpoint (using database)
  def restore_from_checkpoint!(checkpoint_name)
    checkpoint = ConversationCheckpoint.find_by(chat: @chat, checkpoint_name: checkpoint_name)

    unless checkpoint
      raise CheckpointError, "Checkpoint '#{checkpoint_name}' not found"
    end

    begin
      ActiveRecord::Base.transaction do
        # Clear current problematic messages
        messages_after_checkpoint = @chat.messages.where(
          "created_at > ?",
          checkpoint.created_at
        )

        @logger.info "Removing #{messages_after_checkpoint.count} messages after checkpoint"
        messages_after_checkpoint.destroy_all

        # Restore conversation state
        @chat.update!(
          conversation_state: checkpoint.conversation_state || "stable",
          last_stable_at: Time.current
        )

        @logger.info "Restored chat #{@chat.id} from checkpoint '#{checkpoint_name}'"
        true
      end

    rescue => e
      @logger.error "Failed to restore from checkpoint: #{e.message}"
      raise CheckpointError, "Failed to restore conversation: #{e.message}"
    end
  end

  # Automatic state validation and healing
  def validate_and_heal_state!
    begin
      validate_conversation_state!
      @chat.update_column(:conversation_state, "stable")
      { status: :healthy, actions_taken: [] }

    rescue StateValidationError => e
      @logger.warn "Conversation validation failed: #{e.message}"

      actions_taken = []

      # Try progressive healing strategies
      begin
        # Strategy 1: Clean orphaned messages
        orphaned_count = @chat.cleanup_orphaned_messages!
        actions_taken << "cleaned_#{orphaned_count}_orphaned_messages" if orphaned_count > 0

        # Strategy 2: Repair conversation structure
        @conversation_manager.attempt_conversation_repair!
        actions_taken << "repaired_conversation_structure"

        # Re-validate after healing
        validate_conversation_state!
        @chat.update_column(:conversation_state, "stable")

        { status: :healed, actions_taken: actions_taken }

      rescue => healing_error
        @logger.error "Healing failed: #{healing_error.message}"

        # Strategy 3: Create recovery branch if healing fails
        recovery_chat = create_recovery_branch!
        actions_taken << "created_recovery_branch_#{recovery_chat.id}"

        {
          status: :recovery_branch_created,
          actions_taken: actions_taken,
          recovery_chat: recovery_chat
        }
      end
    end
  end

  # Create a conversation branch for error recovery
  def create_recovery_branch!
    begin
      recovery_chat = @chat.user.chats.create!(
        title: "#{@chat.title} (Recovery #{Time.current.strftime('%H:%M')})",
        status: "active",
        conversation_state: "stable",
        model_id: @chat.model_id,
        last_stable_at: Time.current
      )

      # Copy the last stable conversation state
      stable_messages = extract_stable_message_sequence

      stable_messages.each do |msg_data|
        recovery_chat.messages.create!(
          role: msg_data[:role],
          content: msg_data[:content],
          user: msg_data[:role] == "user" ? @chat.user : nil,
          message_type: msg_data[:message_type] || "text",
          metadata: msg_data[:metadata] || {},
          created_at: msg_data[:created_at]
        )
      end

      # Mark original chat as archived due to corruption
      @chat.update!(
        status: "archived",
        title: "#{@chat.title} (Corrupted - #{Time.current.strftime('%H:%M')})",
        conversation_state: "error"
      )

      @logger.info "Created recovery branch chat #{recovery_chat.id} from corrupted chat #{@chat.id}"
      recovery_chat

    rescue => e
      @logger.error "Failed to create recovery branch: #{e.message}"
      raise ConversationBranchError, "Failed to create recovery branch: #{e.message}"
    end
  end

  # Merge conversation branches (for future advanced recovery)
  def merge_branches!(branch_chat, strategy: :append)
    case strategy
    when :append
      merge_by_appending(branch_chat)
    when :interleave
      merge_by_interleaving(branch_chat)
    when :replace
      merge_by_replacing(branch_chat)
    else
      raise ConversationBranchError, "Unknown merge strategy: #{strategy}"
    end
  end

  # Get conversation health metrics
  def health_metrics
    {
      message_count: @chat.messages.count,
      tool_calls_count: @chat.tool_calls.count,
      orphaned_messages: @chat.orphaned_tool_messages.count,
      conversation_state: @chat.conversation_state,
      last_stable_at: @chat.last_stable_at,
      has_integrity_issues: @chat.has_conversation_issues?,
      available_checkpoints: list_available_checkpoints,
      health_score: calculate_health_score
    }
  end

  # List available checkpoints for this chat (using database)
  def list_available_checkpoints
    ConversationCheckpoint.where(chat: @chat)
                         .order(created_at: :desc)
                         .limit(10)
                         .map do |checkpoint|
      {
        name: checkpoint.checkpoint_name,
        created_at: checkpoint.created_at.iso8601,
        message_count: checkpoint.message_count,
        context: checkpoint.context_data
      }
    end
  end

  private

  def validate_conversation_state!
    # Basic structure validation
    unless @chat.messages.exists?
      raise StateValidationError, "Chat has no messages"
    end

    # Check for orphaned tool messages
    orphaned_count = @chat.orphaned_tool_messages.count
    if orphaned_count > 0
      raise StateValidationError, "Chat has #{orphaned_count} orphaned tool messages"
    end

    # Validate tool call/response pairing
    @conversation_manager.validate_tool_call_response_pairing!

    # Check conversation flow
    validate_conversation_flow!
  end

  def validate_conversation_flow!
    messages = @chat.messages.order(:created_at)
    previous_role = nil

    messages.each do |message|
      case message.role
      when "assistant"
        # Assistant messages with tool calls must be followed by tool responses
        if message.tool_calls.any?
          next_messages = messages.where("created_at > ?", message.created_at)
                                 .order(:created_at)
                                 .limit(message.tool_calls.count)

          unless next_messages.all? { |m| m.role == "tool" }
            raise StateValidationError, "Assistant message with tool calls not followed by tool responses"
          end
        end
      end

      previous_role = message.role
    end
  end

  def serialize_messages_for_checkpoint
    @chat.messages.order(:created_at).map do |message|
      {
        id: message.id,
        role: message.role,
        content: message.content,
        message_type: message.message_type,
        tool_call_id: message.tool_call_id,
        metadata: message.metadata,
        created_at: message.created_at.iso8601,
        tool_calls: message.tool_calls.map do |tc|
          {
            tool_call_id: tc.tool_call_id,
            name: tc.name,
            arguments: tc.arguments
          }
        end
      }
    end
  end

  def extract_context_data
    {
      user_id: @chat.user_id,
      chat_title: @chat.title,
      model_id: @chat.model_id,
      last_user_message: @chat.messages.where(role: "user").last&.content,
      total_tokens: @chat.total_tokens,
      conversation_length: @chat.messages.count
    }
  end

  def extract_stable_message_sequence
    # Find the last stable point in conversation
    stable_messages = []

    @chat.messages.order(:created_at).each do |message|
      case message.role
      when "user", "system"
        stable_messages << message_to_hash(message)
      when "assistant"
        if message.tool_calls.empty?
          # Regular assistant message without tools
          stable_messages << message_to_hash(message)
        else
          # Only include if all tool responses are present
          tool_call_ids = message.tool_calls.pluck(:tool_call_id)
          tool_responses = @chat.messages.where(
            role: "tool",
            tool_call_id: tool_call_ids
          )

          if tool_responses.count == tool_call_ids.count
            stable_messages << message_to_hash(message)
            tool_responses.each do |tr|
              stable_messages << message_to_hash(tr)
            end
          else
            # Stop at incomplete tool sequences
            break
          end
        end
      end
    end

    stable_messages
  end

  def message_to_hash(message)
    {
      role: message.role,
      content: message.content,
      message_type: message.message_type,
      tool_call_id: message.tool_call_id,
      metadata: message.metadata,
      created_at: message.created_at
    }
  end

  def load_checkpoint(checkpoint_name)
    checkpoint = ConversationCheckpoint.find_by(chat: @chat, checkpoint_name: checkpoint_name)
    return nil unless checkpoint

    {
      "conversation_state" => checkpoint.conversation_state,
      "created_at" => checkpoint.created_at.iso8601,
      "message_count" => checkpoint.message_count,
      "messages_snapshot" => checkpoint.messages_snapshot,
      "context_data" => checkpoint.context_data
    }
  rescue => e
    @logger.error "Failed to load checkpoint data: #{e.message}"
    nil
  end

  def checkpoint_key(checkpoint_name)
    # Not needed for database implementation, but keeping for compatibility
    "listopia:chat_checkpoint:#{@chat.id}:#{checkpoint_name}"
  end

  def calculate_health_score
    score = 100

    # Deduct for orphaned messages
    orphaned_count = @chat.orphaned_tool_messages.count
    score -= (orphaned_count * 10)

    # Deduct for conversation state issues
    score -= 30 if @chat.conversation_state == "error"
    score -= 15 if @chat.conversation_state == "needs_cleanup"

    # Deduct for old instability
    if @chat.last_stable_at && @chat.last_stable_at < 1.hour.ago
      score -= 20
    end

    # Ensure score is between 0 and 100
    [ score, 0 ].max
  end

  def merge_by_appending(branch_chat)
    # Simple append strategy - add branch messages to main chat
    branch_messages = branch_chat.messages.order(:created_at)

    ActiveRecord::Base.transaction do
      branch_messages.each do |msg|
        @chat.messages.create!(
          role: msg.role,
          content: msg.content,
          user: msg.user,
          message_type: msg.message_type,
          metadata: msg.metadata.merge(merged_from_branch: branch_chat.id)
        )
      end

      branch_chat.update!(status: "archived", title: "#{branch_chat.title} (Merged)")
    end
  end

  def merge_by_interleaving(branch_chat)
    # More complex merge strategy - interleave by timestamp
    raise ConversationBranchError, "Interleaving merge not yet implemented"
  end

  def merge_by_replacing(branch_chat)
    # Replace main chat content with branch content
    ActiveRecord::Base.transaction do
      @chat.messages.destroy_all

      branch_chat.messages.order(:created_at).each do |msg|
        @chat.messages.create!(
          role: msg.role,
          content: msg.content,
          user: msg.user,
          message_type: msg.message_type,
          metadata: msg.metadata
        )
      end

      @chat.update!(conversation_state: "stable", last_stable_at: Time.current)
      branch_chat.update!(status: "archived", title: "#{branch_chat.title} (Replaced Main)")
    end
  end
end
