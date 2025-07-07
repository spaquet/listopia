# app/models/message.rb
# == Schema Information
#
# Table name: messages
#
#  id                :uuid             not null, primary key
#  content           :text
#  context_snapshot  :json
#  input_tokens      :integer
#  llm_model         :string
#  llm_provider      :string
#  message_type      :string           default("text")
#  metadata          :json
#  output_tokens     :integer
#  processing_time   :decimal(8, 3)
#  role              :string           not null
#  token_count       :integer
#  tool_call_results :json
#  tool_calls        :json
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  chat_id           :uuid             not null
#  model_id          :string
#  tool_call_id      :string
#  user_id           :uuid
#
# Indexes
#
#  index_messages_on_chat_id                          (chat_id)
#  index_messages_on_chat_id_and_created_at           (chat_id,created_at)
#  index_messages_on_chat_id_and_role                 (chat_id,role)
#  index_messages_on_chat_id_and_role_and_created_at  (chat_id,role,created_at)
#  index_messages_on_llm_provider_and_llm_model       (llm_provider,llm_model)
#  index_messages_on_message_type                     (message_type)
#  index_messages_on_model_id                         (model_id)
#  index_messages_on_role                             (role)
#  index_messages_on_tool_call_id                     (tool_call_id)
#  index_messages_on_user_id                          (user_id)
#  index_messages_on_user_id_and_created_at           (user_id,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (chat_id => chats.id)
#  fk_rails_...  (user_id => users.id)
#

# This is the AI message sent to the LLM or received from it.
class Message < ApplicationRecord
  # Use RubyLLM's Rails integration
  acts_as_message

  belongs_to :chat
  belongs_to :user, optional: true # Assistant messages don't have a user
  has_many :tool_calls, dependent: :destroy

  validates :role, inclusion: { in: %w[user assistant system tool] }
  validates :message_type, inclusion: { in: %w[text tool_call tool_result] }
  # Note: Don't validate content presence due to RubyLLM's two-phase creation
  # validates :content, presence: true, unless: -> { tool_calls.any? }

  enum :role, {
    user: "user",
    assistant: "assistant",
    system: "system",
    tool: "tool"
  }, prefix: true

  enum :message_type, {
    text: "text",
    tool_call: "tool_call",
    tool_result: "tool_result"
  }, prefix: true

  scope :conversation, -> { where(role: [ "user", "assistant" ]) }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_chat, ->(chat) { where(chat: chat) }

  before_save :calculate_token_count
  after_create :update_chat_timestamp

  def to_llm_format
    case role
    when "user", "assistant", "system"
      base_format = { role: role, content: content }

      # Add tool calls if present
      if tool_calls.any?
        base_format[:tool_calls] = tool_calls
      end

      base_format
    when "tool"
      {
        role: "tool",
        tool_call_id: metadata["tool_call_id"],
        content: content
      }
    end
  end

  def is_from_user?
    role_user?
  end

  def is_from_assistant?
    role_assistant?
  end

  def has_tool_calls?
    tool_calls.any? || (tool_calls_json.present? && tool_calls_json.any?)
  end

  def has_tool_results?
    tool_call_results.any?
  end

  def processing_time_ms
    (processing_time * 1000).to_i if processing_time
  end

  # Helper method to access tool_calls JSON as array
  def tool_calls_json
    read_attribute(:tool_calls) || []
  end

  # Helper method to access tool_call_results JSON as array
  def tool_call_results_json
    read_attribute(:tool_call_results) || []
  end

  private

  def calculate_token_count
    # Simple token estimation - you might want to use a more sophisticated method
    if content.present?
      # Rough estimation: ~4 characters per token for English text
      self.token_count = (content.length / 4.0).ceil
    end
  end

  def update_chat_timestamp
    chat.update_column(:last_message_at, created_at)
  end
end
