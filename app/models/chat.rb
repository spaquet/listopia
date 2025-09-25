# app/models/chat.rb
# == Schema Information
#
# Table name: chats
#
#  id                 :uuid             not null, primary key
#  context            :json
#  conversation_state :string           default("stable")
#  last_cleanup_at    :datetime
#  last_message_at    :datetime
#  last_stable_at     :datetime
#  metadata           :json
#  model_id_string    :string
#  status             :string           default("active")
#  title              :string(255)
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  model_id           :bigint
#  user_id            :uuid             not null
#
# Indexes
#
#  index_chats_on_conversation_state      (conversation_state)
#  index_chats_on_last_message_at         (last_message_at)
#  index_chats_on_last_stable_at          (last_stable_at)
#  index_chats_on_model_id                (model_id)
#  index_chats_on_model_id_string         (model_id_string)
#  index_chats_on_user_id                 (user_id)
#  index_chats_on_user_id_and_created_at  (user_id,created_at)
#  index_chats_on_user_id_and_status      (user_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (model_id => models.id)
#  fk_rails_...  (user_id => users.id)
#
class Chat < ApplicationRecord
  # Use RubyLLM's Rails integration
  acts_as_chat messages: :messages, message_class: "Message", model: :model

  belongs_to :user
  belongs_to :model, optional: true
  has_many :messages, dependent: :destroy
  has_many :tool_calls, through: :messages
  has_many :conversation_contexts, dependent: :destroy
  has_many :conversation_checkpoints, dependent: :destroy
  has_many :recovery_contexts, dependent: :destroy

  validates :title, presence: true, length: { maximum: 255 }
  validates :status, inclusion: { in: %w[active archived completed workflow_planning error] }
  validates :conversation_state, inclusion: { in: %w[stable needs_cleanup error] }

  enum :status, {
    active: "active",
    archived: "archived",
    completed: "completed",
    workflow_planning: "workflow_planning",
    error: "error"
  }, prefix: true

  enum :conversation_state, {
    stable: "stable",
    needs_cleanup: "needs_cleanup",
    error: "error"
  }, prefix: true

  scope :recent, -> { order(last_message_at: :desc, created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }
  scope :active_chats, -> { where(status: "active") }

  before_create :set_default_title
  after_update :update_last_message_timestamp, if: :saved_change_to_last_message_at?

  # Override RubyLLM's ask method to ensure conversation integrity
  def ask(message_content, **options)
    Rails.logger.debug "Chat#ask called for chat #{id} with message: #{message_content[0..100]}..."

    # Track tool calls before and after to validate responses
    pre_call_tool_ids = Set.new(tool_calls.pluck(:tool_call_id))

    begin
      # Clean conversation before making the API call
      clean_conversation_for_api_call!

      # Call RubyLLM's ask method
      response = super(message_content, **options)

      # Validate tool call responses after the call
      post_call_tool_ids = Set.new(tool_calls.pluck(:tool_call_id))
      new_tool_ids = post_call_tool_ids - pre_call_tool_ids

      if new_tool_ids.any?
        validate_new_tool_responses(new_tool_ids)
      end

      # Mark conversation as stable
      update_column(:conversation_state, "stable")
      update_column(:last_stable_at, Time.current)

      response

    rescue RubyLLM::BadRequestError => e
      handle_api_error(e, message_content, options)
    rescue ConversationStateManager::ConversationError => e
      handle_conversation_error(e, message_content, options)
    rescue => e
      Rails.logger.error "Error in Chat#ask: #{e.class.name} - #{e.message}"
      raise e
    end
  end

  # Clean conversation state before API call
  def clean_conversation_for_api_call!
    conversation_manager = ConversationStateManager.new(self)

    begin
      conversation_manager.ensure_conversation_integrity!
    rescue ConversationStateManager::ConversationError => e
      Rails.logger.warn "Cleaning conversation issues before API call: #{e.message}"

      # Perform comprehensive cleanup
      cleanup_count = conversation_manager.perform_comprehensive_cleanup!

      if cleanup_count > 0
        Rails.logger.info "Cleaned up #{cleanup_count} problematic messages before API call"
        update_column(:conversation_state, "stable")
      end
    end
  end

  # Validate that new tool calls have corresponding responses
  def validate_new_tool_responses(new_tool_ids)
    tool_response_manager = ToolResponseManager.new(self)

    new_tool_ids.each do |tool_call_id|
      unless tool_response_manager.tool_call_has_response?(tool_call_id)
        Rails.logger.warn "Tool call #{tool_call_id} missing response message"

        # Create placeholder response to maintain conversation integrity
        begin
          tool_response_manager.create_tool_response(
            tool_call_id: tool_call_id,
            content: "Tool execution completed",
            metadata: { auto_generated: true, reason: "missing_response" }
          )
        rescue => e
          Rails.logger.error "Failed to create placeholder response: #{e.message}"
        end
      end
    end
  end

  # Handle API errors with conversation repair
  def handle_api_error(error, message_content, options)
    Rails.logger.error "API Error in chat #{id}: #{error.message}"

    if conversation_structure_error?(error)
      Rails.logger.warn "Conversation structure error detected, attempting repair"

      # Mark as needing cleanup
      update_column(:conversation_state, "needs_cleanup")

      # Attempt repair
      repair_conversation_and_retry(message_content, options)
    else
      # Re-raise non-conversation errors
      raise error
    end
  end

  # Handle conversation state errors
  def handle_conversation_error(error, message_content, options)
    Rails.logger.error "Conversation Error in chat #{id}: #{error.message}"

    update_column(:conversation_state, "error")

    # Attempt aggressive repair
    repair_conversation_and_retry(message_content, options)
  end

  # Repair conversation and retry the request
  def repair_conversation_and_retry(message_content, options)
    conversation_manager = ConversationStateManager.new(self)

    # Perform comprehensive cleanup
    cleanup_count = conversation_manager.perform_comprehensive_cleanup!

    Rails.logger.info "Repaired conversation: cleaned #{cleanup_count} messages"

    if cleanup_count > 0
      # Mark as stable and retry
      update_columns(
        conversation_state: "stable",
        last_stable_at: Time.current
      )

      # Retry the API call once
      begin
        super(message_content, **options)
      rescue => retry_error
        Rails.logger.error "Retry failed even after repair: #{retry_error.message}"
        raise retry_error
      end
    else
      # If no cleanup was needed, the issue might be elsewhere
      raise ConversationStateManager::ConversationError, "Unable to repair conversation state"
    end
  end

  # Check if error is related to conversation structure
  def conversation_structure_error?(error)
    error_patterns = [
      /tool_calls.*must be followed by tool messages/i,
      /tool_call_id.*did not have response messages/i,
      /assistant message.*tool_calls.*must be followed/i,
      /invalid.*parameter.*messages/i,
      /missing.*parameter.*tool_call_id/i,
      /tool.*must have.*tool_call_id/i
    ]

    error_patterns.any? { |pattern| error.message.match?(pattern) }
  end

  # Get conversation statistics
  def conversation_stats
    {
      total_messages: messages.count,
      user_messages: messages.where(role: "user").count,
      assistant_messages: messages.where(role: "assistant").count,
      tool_messages: messages.where(role: "tool").count,
      system_messages: messages.where(role: "system").count,
      tool_calls_count: tool_calls.count,
      orphaned_tool_messages: orphaned_tool_messages.count,
      conversation_state: conversation_state,
      last_stable_at: last_stable_at,
      has_issues: has_conversation_issues?
    }
  end

  # Find orphaned tool messages
  def orphaned_tool_messages
    messages.where(role: "tool").left_joins(:chat)
           .joins("LEFT JOIN tool_calls ON tool_calls.tool_call_id = messages.tool_call_id")
           .where(tool_calls: { tool_call_id: nil })
           .or(messages.where(role: "tool", tool_call_id: [ nil, "" ]))
  end

  # Check if conversation has issues
  def has_conversation_issues?
    conversation_manager = ConversationStateManager.new(self)

    begin
      conversation_manager.ensure_conversation_integrity!
      false
    rescue ConversationStateManager::ConversationError
      true
    end
  end

  # Repair conversation issues
  def repair_conversation!
    conversation_manager = ConversationStateManager.new(self)
    cleanup_count = conversation_manager.perform_comprehensive_cleanup!

    update_columns(
      conversation_state: "stable",
      last_stable_at: Time.current
    )

    cleanup_count
  end

  # Get safe conversation history for API calls
  def safe_conversation_history
    conversation_manager = ConversationStateManager.new(self)
    conversation_manager.clean_conversation_history
  end

  # Create checkpoint for conversation state
  def create_checkpoint!(name)
    conversation_checkpoints.create!(
      checkpoint_name: name,
      message_count: messages.count,
      tool_calls_count: tool_calls.count,
      conversation_state: conversation_state,
      messages_snapshot: messages.order(:created_at).to_json,
      context_data: conversation_stats.to_json
    )
  end

  # Add assistant message safely
  def add_assistant_message(content, metadata: {})
    messages.create!(
      role: "assistant",
      content: content,
      message_type: "text",
      metadata: metadata,
      user: nil # Assistant messages don't have a user
    )
  end

  # Calculate total tokens used
  def total_tokens
    messages.sum { |m| (m.input_tokens || 0) + (m.output_tokens || 0) }
  end

  # Calculate total processing time
  def total_processing_time
    messages.sum(:processing_time) || 0
  end

  # Get latest messages for chat history loading
  def latest_messages(limit = 50)
    messages.order(created_at: :desc).limit(limit).reverse
  end

  # Alternative method that includes eager loading for better performance
  def latest_messages_with_includes(limit = 50)
    messages.includes(:user, :tool_calls)
            .order(created_at: :desc)
            .limit(limit)
            .reverse
  end

  # Get recent conversation context (last few messages)
  def recent_context(limit = 5)
    messages.order(created_at: :desc)
            .limit(limit)
            .reverse
            .map { |msg| "#{msg.role}: #{msg.content&.truncate(100)}" }
            .join("\n")
  end

  private

  def set_default_title
    self.title ||= "Chat #{Time.current.strftime('%m/%d %H:%M')}"
  end

  def update_last_message_timestamp
    self.last_message_at = Time.current if messages.any?
  end
end
