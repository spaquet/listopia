# app/models/tool_call.rb
# == Schema Information
#
# Table name: tool_calls
#
#  id           :uuid             not null, primary key
#  arguments    :jsonb
#  name         :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  message_id   :uuid             not null
#  tool_call_id :string           not null
#
# Indexes
#
#  index_tool_calls_on_message_id                 (message_id)
#  index_tool_calls_on_message_id_and_created_at  (message_id,created_at)
#  index_tool_calls_on_name                       (name)
#  index_tool_calls_on_tool_call_id               (tool_call_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (message_id => messages.id)
#
class ToolCall < ApplicationRecord
  # Use RubyLLM 1.8 standard approach - let it handle everything
  acts_as_tool_call

  belongs_to :message

  validates :tool_call_id, presence: true, uniqueness: true
  validates :name, presence: true

  scope :for_message, ->(message) { where(message: message) }
  scope :by_name, ->(name) { where(name: name) }
  scope :recent, -> { order(created_at: :desc) }

  # Keep only essential helper methods
  def arguments_hash
    arguments || {}
  end
end
