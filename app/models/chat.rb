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
  # Use RubyLLM 1.8 standard approach - let it handle everything
  acts_as_chat

  belongs_to :user
  belongs_to :model, optional: true
  has_many :messages, dependent: :destroy
  has_many :tool_calls, through: :messages

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

  # Keep only essential business logic methods

  def conversation_stats
    {
      total_messages: messages.count,
      user_messages: messages.where(role: "user").count,
      assistant_messages: messages.where(role: "assistant").count,
      tool_messages: messages.where(role: "tool").count,
      system_messages: messages.where(role: "system").count,
      tool_calls_count: tool_calls.count,
      conversation_state: conversation_state,
      last_stable_at: last_stable_at
    }
  end

  # Calculate total tokens used
  def total_tokens
    messages.sum { |m| (m.input_tokens || 0) + (m.output_tokens || 0) }
  end

  # Calculate total processing time
  def total_processing_time
    messages.sum(:processing_time) || 0
  end

  # Get latest messages for chat history loading with performance optimization
  def latest_messages_with_includes(limit = 50)
    messages.displayable
            .includes(:user, :tool_calls)
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
