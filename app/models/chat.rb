# app/models/chat.rb
# == Schema Information
#
# Table name: chats
#
#  id              :uuid             not null, primary key
#  context         :json
#  last_message_at :datetime
#  metadata        :json
#  status          :string           default("active")
#  title           :string(255)
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  model_id        :string
#  user_id         :uuid             not null
#
# Indexes
#
#  index_chats_on_last_message_at         (last_message_at)
#  index_chats_on_model_id                (model_id)
#  index_chats_on_user_id                 (user_id)
#  index_chats_on_user_id_and_created_at  (user_id,created_at)
#  index_chats_on_user_id_and_status      (user_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
# app/models/chat.rb
# app/models/chat.rb
class Chat < ApplicationRecord
  # Use RubyLLM's Rails integration
  acts_as_chat

  belongs_to :user
  has_many :messages, dependent: :destroy
  has_many :tool_calls, through: :messages

  validates :user, presence: true
  validates :status, inclusion: { in: %w[active archived completed] }

  enum :status, {
    active: "active",
    archived: "archived",
    completed: "completed"
  }, prefix: true

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
    safe_messages = messages.where(role: ['user', 'assistant'])
                           .where('content IS NOT NULL AND content != ?', '')
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
      user_messages: messages.where(role: 'user').count,
      assistant_messages: messages.where(role: 'assistant').count,
      tool_messages: messages.where(role: 'tool').count,
      system_messages: messages.where(role: 'system').count,
      tool_calls: tool_calls.count,
      orphaned_tool_messages: orphaned_tool_messages.count,
      has_issues: has_conversation_issues?
    }
  end

  def total_tokens
    messages.sum { |m| (m.input_tokens || 0) + (m.output_tokens || 0) }
  end

  def total_processing_time
    messages.sum(:processing_time)
  end

  # Find messages that might be problematic
  def orphaned_tool_messages
    messages.where(role: 'tool').select do |tool_msg|
      tool_msg.tool_call_id.blank? ||
      !tool_calls.exists?(tool_call_id: tool_msg.tool_call_id)
    end
  end

  # Clean up any orphaned or problematic messages
  def cleanup_orphaned_messages!
    orphaned_count = orphaned_tool_messages.count
    orphaned_tool_messages.each(&:destroy!)

    Rails.logger.info "Cleaned up #{orphaned_count} orphaned tool messages from chat #{id}" if orphaned_count > 0

    orphaned_count
  end

  # Override RubyLLM's ask method to ensure conversation integrity
  def ask(message_content, **options)
    # Ensure conversation integrity before making the API call
    begin
      conversation_manager = ConversationStateManager.new(self)
      conversation_manager.ensure_conversation_integrity!
    rescue ConversationStateManager::ConversationError => e
      Rails.logger.warn "Conversation integrity issue detected before API call: #{e.message}"
      # Let the conversation manager attempt repair
    end

    # Call the original RubyLLM ask method
    super(message_content, **options)
  end

  private

  def set_default_title
    self.title ||= "Chat #{Time.current.strftime('%m/%d %H:%M')}"
  end

  def update_last_message_timestamp
    self.update_column(:last_message_at, Time.current) if messages.any?
  end
end
