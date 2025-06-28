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

  def conversation_history
    messages.where(role: [ "user", "assistant" ])
           .order(created_at: :asc)
           .map(&:to_llm_format)
  end

  # Remove custom add_user_message and add_assistant_message methods
  # RubyLLM's acts_as_chat will provide these automatically

  def total_tokens
    messages.sum { |m| (m.input_tokens || 0) + (m.output_tokens || 0) }
  end

  def total_processing_time
    messages.sum(:processing_time)
  end

  private

  def set_default_title
    self.title ||= "Chat #{Time.current.strftime('%m/%d %H:%M')}"
  end

  def update_last_message_timestamp
    self.update_column(:last_message_at, Time.current) if messages.any?
  end
end
