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
#  index_tool_calls_on_message_id    (message_id)
#  index_tool_calls_on_name          (name)
#  index_tool_calls_on_tool_call_id  (tool_call_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (message_id => messages.id)
#
class ToolCall < ApplicationRecord
  acts_as_tool_call
end
