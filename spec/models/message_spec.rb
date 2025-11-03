# == Schema Information
#
# Table name: messages
#
#  id                    :uuid             not null, primary key
#  cache_creation_tokens :integer
#  cached_tokens         :integer
#  content               :text
#  content_raw           :json
#  context_snapshot      :json
#  input_tokens          :integer
#  llm_model             :string
#  llm_provider          :string
#  message_type          :string           default("text")
#  metadata              :json
#  model_id_string       :string
#  output_tokens         :integer
#  processing_time       :decimal(8, 3)
#  role                  :string           not null
#  token_count           :integer
#  tool_call_results     :json
#  tool_calls            :json
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  chat_id               :uuid             not null
#  model_id              :bigint
#  tool_call_id          :string
#  user_id               :uuid
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
require 'rails_helper'

RSpec.describe Message, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
