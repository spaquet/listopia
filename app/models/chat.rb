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
  acts_as_chat

  belongs_to :user
  belongs_to :model, optional: true
  has_many :conversation_contexts, dependent: :destroy
  has_many :messages, dependent: :destroy
  has_many :tool_calls, through: :messages

  validates :user, presence: true
  validates :status, inclusion: { in: %w[active archived completed] }

  # Define chat status with enum for better readability and management
  enum :status, {
    active: "active",
    archived: "archived",
    completed: "completed"
  }, prefix: true

  # Define conversation states for integrity management
  enum :conversation_state, {
    stable: "stable",
    needs_cleanup: "needs_cleanup",
    error: "error"
  }, prefix: true, default: "stable"

  scope :recent, -> { order(last_message_at: :desc, created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }

  before_create :set_default_title
  after_update :update_last_message_timestamp, if: :saved_change_to_updated_at?

  def latest_messages(limit = 50)
    messages.order(created_at: :desc).limit(limit).reverse
  end

  # Enhanced conversation history with integrity checking
  def conversation_history
    conversation_manager = ConversationStateManager.new(self)
    conversation_manager.clean_conversation_history
  rescue ConversationStateManager::ConversationError => e
    Rails.logger.error "Conversation integrity error for chat #{id}: #{e.message}"

    # Fallback: return basic conversation without problematic messages
    safe_messages = messages.where(role: [ "user", "assistant" ])
                           .where("content IS NOT NULL AND content != ?", "")
                           .order(created_at: :asc)
                           .map { |m| { role: m.role, content: m.content } }

    safe_messages
  end

  # Check if this chat has conversation integrity issues
  def has_conversation_issues?
    conversation_manager = ConversationStateManager.new(self)
    conversation_manager.ensure_conversation_integrity!
    false
  rescue ConversationStateManager::ConversationError
    true
  end

  # Repair conversation integrity
  def repair_conversation!
    conversation_manager = ConversationStateManager.new(self)
    conversation_manager.ensure_conversation_integrity!
  end

  # Get conversation statistics
  def conversation_stats
    {
      total_messages: messages.count,
      user_messages: messages.where(role: "user").count,
      assistant_messages: messages.where(role: "assistant").count,
      tool_messages: messages.where(role: "tool").count,
      system_messages: messages.where(role: "system").count,
      tool_calls: tool_calls.count,
      orphaned_tool_messages: orphaned_tool_messages.count,
      has_issues: has_conversation_issues?
    }
  end

  def add_assistant_message(content, metadata: {})
    messages.create!(
      role: "assistant",
      content: content,
      message_type: "text",
      metadata: metadata,
      user: nil # Assistant messages don't have a user
    )
  end

  def total_tokens
    messages.sum { |m| (m.input_tokens || 0) + (m.output_tokens || 0) }
  end

  def total_processing_time
    messages.sum(:processing_time)
  end

  # Find messages that might be problematic
  def orphaned_tool_messages
    messages.where(role: "tool").select do |tool_msg|
      tool_msg.tool_call_id.blank? ||
      !tool_calls.exists?(tool_call_id: tool_msg.tool_call_id)
    end
  end

  # Clean up any orphaned or problematic messages
  def cleanup_orphaned_messages!
    orphaned_count = orphaned_tool_messages.count
    orphaned_tool_messages.each(&:destroy!)

    if orphaned_count > 0
      Rails.logger.info "Cleaned up #{orphaned_count} orphaned tool messages from chat #{id}"
      update_column(:last_cleanup_at, Time.current)
      update_column(:conversation_state, "stable")
    end

    orphaned_count
  end

  # Override RubyLLM's ask method to ensure conversation integrity
  def ask(message_content, **options)
    pre_call_tool_ids = Set.new(tool_calls.pluck(:tool_call_id))

    begin
      # Clean conversation before making the API call
      clean_conversation_for_api_call!

      response = super(message_content, **options)

      post_call_tool_ids = Set.new(tool_calls.pluck(:tool_call_id))
      new_tool_ids = post_call_tool_ids - pre_call_tool_ids

      if new_tool_ids.any?
        begin
          validate_new_tool_responses(new_tool_ids)
        rescue => e
          Rails.logger.warn "Tool validation error (non-critical): #{e.message}"
        end
      end

      response
    rescue RubyLLM::BadRequestError => e
      # If it's a conversation structure error, clean up and try again
      if conversation_structure_error?(e)
        Rails.logger.warn "Conversation structure error detected, cleaning and retrying: #{e.message}"
        update_column(:conversation_state, "needs_cleanup")  # ADD THIS LINE
        cleanup_conversation_for_retry!

        # Try one more time with cleaned conversation
        response = super(message_content, **options)
        update_column(:conversation_state, "stable")  # ADD THIS LINE
        response
      else
        raise e
      end
    rescue ConversationStateManager::ConversationError => e
      Rails.logger.warn "Conversation integrity issue: #{e.message}"
      response = super(message_content, **options)
    rescue => e
      Rails.logger.error "Error in Chat#ask: #{e.message}"
      raise e
    end
  end

  # Only allow aggressive cleanup on conversations that haven't been active recently
  def safe_for_aggressive_cleanup?
    return false if last_stable_at.nil?
    return false if last_stable_at > 1.hour.ago
    return false if messages.where("created_at > ?", 10.minutes.ago).exists?

    true
  end

  # Get contexts related to this chat
  def related_contexts(limit: 10)
    conversation_contexts
      .active
      .recent
      .limit(limit)
  end

  # Get session context summary
  def session_context_summary
    contexts = related_contexts(50)

    {
      total_actions: contexts.count,
      unique_entities: contexts.distinct.count(:entity_id),
      entity_types: contexts.distinct.pluck(:entity_type),
      actions: contexts.group(:action).count,
      session_started: contexts.minimum(:created_at)
    }
  end

  private

  def set_default_title
    self.title ||= "Chat #{Time.current.strftime('%m/%d %H:%M')}"
  end

  def update_last_message_timestamp
    self.update_column(:last_message_at, Time.current) if messages.any?
  end

  def validate_new_tool_responses(new_tool_ids)
    # Validate that all new tool calls have corresponding responses
    new_tool_ids.each do |tool_call_id|
      unless messages.exists?(role: "tool", tool_call_id: tool_call_id)
        Rails.logger.warn "Tool call #{tool_call_id} missing response message"
      end
    end
  end

  def conversation_structure_error?(error)
    error_patterns = [
      /tool_calls.*must be followed by tool messages/i,
      /tool_call_id.*did not have response messages/i,
      /assistant message.*tool_calls.*must be followed/i,
      /invalid.*parameter.*messages/i
    ]

    error_patterns.any? { |pattern| error.message.match?(pattern) }
  end

  def clean_conversation_for_api_call!
    # Remove any incomplete tool call sequences before making API call
    conversation_manager = ConversationStateManager.new(self)

    begin
      conversation_manager.ensure_conversation_integrity!
    rescue ConversationStateManager::ConversationError => e
      Rails.logger.warn "Cleaning conversation issues before API call: #{e.message}"
      cleanup_orphaned_messages!
    end
  end

  def cleanup_conversation_for_retry!
    Rails.logger.info "Cleaning up conversation for retry on chat #{id}"

    # Remove orphaned tool messages
    cleanup_orphaned_messages!

    # Remove assistant messages with tool calls that don't have responses
    assistant_messages_with_orphaned_calls = messages.where(role: "assistant")
                                                    .includes(:tool_calls)
                                                    .select do |msg|
      msg.tool_calls.any? && !all_tool_calls_have_responses?(msg)
    end

    if assistant_messages_with_orphaned_calls.any?
      Rails.logger.warn "Removing #{assistant_messages_with_orphaned_calls.count} assistant messages with orphaned tool calls"
      assistant_messages_with_orphaned_calls.each(&:destroy!)
    end

    # Mark conversation as cleaned
    update_column(:last_stable_at, Time.current)
    update_column(:conversation_state, "stable")
  end

  def all_tool_calls_have_responses?(assistant_message)
    tool_call_ids = assistant_message.tool_calls.pluck(:tool_call_id)
    return true if tool_call_ids.empty?

    tool_call_ids.all? do |tool_call_id|
      messages.exists?(role: "tool", tool_call_id: tool_call_id)
    end
  end
end
