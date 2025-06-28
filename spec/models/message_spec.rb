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
require 'rails_helper'

RSpec.describe Message, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
