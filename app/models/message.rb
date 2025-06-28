# app/models/message.rb
# == Schema Information
#
# Table name: messages
#
#  id                :uuid             not null, primary key
#  content           :text
#  context_snapshot  :json
#  llm_model         :string
#  llm_provider      :string
#  message_type      :string           default("text")
#  metadata          :json
#  processing_time   :decimal(8, 3)
#  role              :string           not null
#  token_count       :integer
#  tool_call_results :json
#  tool_calls        :json
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  chat_id           :uuid             not null
#  user_id           :uuid
#
# Indexes
#
#  index_messages_on_chat_id                 (chat_id)
#  index_messages_on_chat_id_and_created_at  (chat_id,created_at)
#  index_messages_on_chat_id_and_role        (chat_id,role)
#  index_messages_on_message_type            (message_type)
#  index_messages_on_role                    (role)
#  index_messages_on_user_id                 (user_id)
#  index_messages_on_user_id_and_created_at  (user_id,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (chat_id => chats.id)
#  fk_rails_...  (user_id => users.id)
#
class Message < ApplicationRecord
  include RubyLlm::ActsAsMessage

  belongs_to :chat
  belongs_to :user, optional: true # Assistant messages don"t have a user

  validates :role, inclusion: { in: %w[user assistant system tool] }
  validates :message_type, inclusion: { in: %w[text tool_call tool_result] }
  validates :content, presence: true, unless: -> { tool_calls.any? }

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
    tool_calls.any?
  end

  def successful_tool_calls
    tool_call_results.select { |result| result["success"] == true }
  end

  def failed_tool_calls
    tool_call_results.select { |result| result["success"] == false }
  end

  def processing_summary
    {
      token_count: token_count,
      processing_time: processing_time,
      tool_calls_count: tool_calls.count,
      successful_tools: successful_tool_calls.count,
      failed_tools: failed_tool_calls.count,
      llm_provider: llm_provider,
      llm_model: llm_model
    }
  end

  private

  def calculate_token_count
    # Simple token estimation - you might want to use a proper tokenizer
    self.token_count = content.to_s.split.count * 1.3 # Rough approximation
  end

  def update_chat_timestamp
    chat.touch(:last_message_at)
  end
end
