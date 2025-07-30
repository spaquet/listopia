# app/models/conversation_checkpoint.rb
# == Schema Information
#
# Table name: conversation_checkpoints
#
#  id                 :uuid             not null, primary key
#  checkpoint_name    :string           not null
#  context_data       :text
#  conversation_state :string           default("stable")
#  message_count      :integer          default(0), not null
#  messages_snapshot  :text
#  tool_calls_count   :integer          default(0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  chat_id            :uuid             not null
#
# Indexes
#
#  index_conversation_checkpoints_on_chat_id                      (chat_id)
#  index_conversation_checkpoints_on_chat_id_and_checkpoint_name  (chat_id,checkpoint_name) UNIQUE
#  index_conversation_checkpoints_on_created_at                   (created_at)
#
# Foreign Keys
#
#  fk_rails_...  (chat_id => chats.id)
#
class ConversationCheckpoint < ApplicationRecord
  belongs_to :chat

  validates :checkpoint_name, presence: true
  validates :checkpoint_name, uniqueness: { scope: :chat_id }
  validates :message_count, :tool_calls_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :conversation_state, inclusion: { in: %w[stable needs_cleanup error] }

  # Rails 8 JSON serialization
  serialize :messages_snapshot, type: Array, coder: JSON
  serialize :context_data, type: Hash, coder: JSON

  scope :recent, -> { order(created_at: :desc) }
  scope :for_chat, ->(chat) { where(chat: chat) }

  # Clean up old checkpoints (7+ days)
  scope :expired, -> { where("created_at < ?", 7.days.ago) }

  def self.cleanup_expired!
    expired.destroy_all
  end
end
