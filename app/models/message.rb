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
#  model_id_string   :string
#  output_tokens     :integer
#  processing_time   :decimal(8, 3)
#  role              :string           not null
#  token_count       :integer
#  tool_call_results :json
#  tool_calls        :json
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  chat_id           :uuid             not null
#  model_id          :bigint
#  tool_call_id      :string
#  user_id           :uuid
#
# Indexes
#
#  index_messages_on_chat_and_tool_call_id            (chat_id,tool_call_id) WHERE (tool_call_id IS NOT NULL)
#  index_messages_on_chat_id                          (chat_id)
#  index_messages_on_chat_id_and_created_at           (chat_id,created_at)
#  index_messages_on_chat_id_and_role                 (chat_id,role)
#  index_messages_on_chat_id_and_role_and_created_at  (chat_id,role,created_at)
#  index_messages_on_chat_id_and_tool_call_id         (chat_id,tool_call_id) WHERE (tool_call_id IS NOT NULL)
#  index_messages_on_llm_provider_and_llm_model       (llm_provider,llm_model)
#  index_messages_on_message_type                     (message_type)
#  index_messages_on_model_id                         (model_id)
#  index_messages_on_model_id_string                  (model_id_string)
#  index_messages_on_role                             (role)
#  index_messages_on_role_and_tool_call_id            (role,tool_call_id) WHERE (((role)::text = 'tool'::text) AND (tool_call_id IS NOT NULL))
#  index_messages_on_tool_call_id                     (tool_call_id)
#  index_messages_on_user_id                          (user_id)
#  index_messages_on_user_id_and_created_at           (user_id,created_at)
#  index_messages_unique_tool_call_id_per_chat        (chat_id,tool_call_id) UNIQUE WHERE (((role)::text = 'tool'::text) AND (tool_call_id IS NOT NULL))
#
# Foreign Keys
#
#  fk_rails_...  (chat_id => chats.id)
#  fk_rails_...  (model_id => models.id)
#  fk_rails_...  (user_id => users.id)
#
class Message < ApplicationRecord
  # Use RubyLLM's Rails integration
  acts_as_message chat: :chat, chat_class: "Chat", tool_calls: :tool_calls, tool_call_class: "ToolCall", model: :model

  belongs_to :chat
  belongs_to :user, optional: true # Assistant messages don't have a user
  belongs_to :model, optional: true
  has_many :tool_calls, dependent: :destroy

  validates :role, inclusion: { in: %w[user assistant system tool] }
  validates :message_type, inclusion: { in: %w[text tool_call tool_result] }
  validates :tool_call_id, uniqueness: {
    scope: :chat_id,
    allow_blank: true
  }, if: :tool_message_with_tool_call_id?
  validate :tool_message_must_have_valid_tool_call_id, if: :should_validate_tool_call_id?

  # Custom validation to ensure tool messages have valid tool_call_id
  validate :tool_message_must_have_valid_tool_call_id, if: :tool_message?

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
  scope :tool_messages, -> { where(role: "tool") }
  scope :orphaned_tool_messages, -> {
    tool_messages.left_joins(chat: { messages: :tool_calls })
                 .where(tool_calls: { tool_call_id: nil })
                 .or(tool_messages.where(tool_call_id: [ nil, "" ]))
  }

  before_validation :handle_duplicate_tool_call_ids, if: :tool_message?
  before_validation :ensure_tool_call_id_format, if: :tool_message?
  before_save :calculate_token_count
  after_create :update_chat_timestamp

  def tool_message?
    role == "tool"
  end

  def to_llm_format
    case role
    when "user", "assistant", "system"
      base_format = { role: role, content: content }

      # Add tool calls if present
      if tool_calls.any?
        base_format[:tool_calls] = tool_calls.map do |tc|
          {
            id: tc.tool_call_id,
            type: "function",
            function: {
              name: tc.name,
              arguments: tc.arguments
            }
          }
        end
      end

      base_format
    when "tool"
      {
        role: "tool",
        tool_call_id: tool_call_id,
        content: content || ""
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

  # Find the corresponding tool call for this tool message
  def corresponding_tool_call
    return nil unless tool_message? && tool_call_id.present?

    chat.tool_calls.find_by(tool_call_id: tool_call_id)
  end

  # Check if this tool message has a valid corresponding tool call
  def has_valid_tool_call?
    return true unless tool_message?

    corresponding_tool_call.present?
  end

  # Create a tool response message with proper linking
  def self.create_tool_response!(chat:, tool_call_id:, content:, metadata: {})
    # Validate that the tool_call_id exists
    tool_call = chat.tool_calls.find_by(tool_call_id: tool_call_id)
    raise ArgumentError, "No tool call found with ID: #{tool_call_id}" unless tool_call

    # Create the tool response message
    create!(
      chat: chat,
      role: "tool",
      tool_call_id: tool_call_id,
      content: content,
      message_type: "tool_result",
      metadata: metadata.merge(
        tool_name: tool_call.name,
        tool_call_created_at: tool_call.created_at
      )
    )
  end

  private

  def tool_message_must_have_valid_tool_call_id
    return unless tool_message?

    if tool_call_id.blank?
      errors.add(:tool_call_id, "cannot be blank for tool messages")
      return
    end

    # Validate format (should start with 'call_' for OpenAI)
    unless tool_call_id.start_with?("call_")
      errors.add(:tool_call_id, "must start with 'call_' for OpenAI compatibility")
    end

    # Check if tool call exists (only if chat is persisted)
    if chat&.persisted? && !chat.tool_calls.exists?(tool_call_id: tool_call_id)
      errors.add(:tool_call_id, "must correspond to an existing tool call")
    end
  end

  def ensure_tool_call_id_format
    return unless tool_message? && tool_call_id.present?

    # Ensure tool_call_id follows OpenAI format
    unless tool_call_id.start_with?("call_")
      self.tool_call_id = "call_#{tool_call_id}" if tool_call_id.present?
    end
  end

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

  def tool_message_with_tool_call_id?
    tool_message? && tool_call_id.present?
  end

  def handle_duplicate_tool_call_ids
    return unless tool_message? && tool_call_id.present?

    existing_message = chat.messages.where(
      role: "tool",
      tool_call_id: tool_call_id
    ).where.not(id: id).first

    if existing_message
      Rails.logger.warn "Duplicate tool_call_id #{tool_call_id} detected, handling gracefully"
      base_id = tool_call_id.gsub(/_\d+$/, "")
      self.tool_call_id = "#{base_id}_#{Time.current.to_i}"
      Rails.logger.info "Updated tool_call_id to #{self.tool_call_id}"
    end
  end

  def should_validate_tool_call_id?
    tool_message? && persisted? && !during_ruby_llm_17_operations?
  end

  def during_ruby_llm_17_operations?
    caller_string = caller.join("\n")
    ruby_llm_17_patterns = [
      /acts_as_message/, /acts_as_chat/, /ruby_llm.*persistence/,
      /ruby_llm.*complete/, /persist.*completion/
    ]
    ruby_llm_17_patterns.any? { |pattern| caller_string.match?(pattern) }
  end
end
