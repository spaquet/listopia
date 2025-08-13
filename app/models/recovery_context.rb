# app/models/recovery_context.rb
# == Schema Information
#
# Table name: recovery_contexts
#
#  id           :uuid             not null, primary key
#  context_data :text
#  expires_at   :datetime         not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  chat_id      :uuid             not null
#  user_id      :uuid             not null
#
# Indexes
#
#  index_recovery_contexts_on_chat_id              (chat_id)
#  index_recovery_contexts_on_created_at           (created_at)
#  index_recovery_contexts_on_expires_at           (expires_at)
#  index_recovery_contexts_on_user_id              (user_id)
#  index_recovery_contexts_on_user_id_and_chat_id  (user_id,chat_id)
#
# Foreign Keys
#
#  fk_rails_...  (chat_id => chats.id)
#  fk_rails_...  (user_id => users.id)
#
class RecoveryContext < ApplicationRecord
  belongs_to :user
  belongs_to :chat

  validates :expires_at, presence: true
  validates :context_data, presence: true

  # Rails 8 JSON serialization
  serialize :context_data, type: Hash, coder: JSON

  scope :active, -> { where("expires_at > ?", Time.current) }
  scope :expired, -> { where("expires_at <= ?", Time.current) }

  # Clean up expired contexts
  def self.cleanup_expired!
    expired.destroy_all
  end

  def expired?
    expires_at <= Time.current
  end
end
