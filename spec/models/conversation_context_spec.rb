# == Schema Information
#
# Table name: conversation_contexts
#
#  id              :uuid             not null, primary key
#  action          :string(50)       not null
#  entity_data     :jsonb            not null
#  entity_type     :string(50)       not null
#  expires_at      :datetime
#  metadata        :jsonb            not null
#  relevance_score :integer          default(100), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  chat_id         :uuid
#  entity_id       :uuid             not null
#  user_id         :uuid             not null
#
# Indexes
#
#  idx_contexts_user_entity_time                          (user_id,entity_type,entity_id,created_at DESC)
#  idx_on_user_id_action_created_at_a6d0f1b259            (user_id,action,created_at DESC)
#  idx_on_user_id_entity_type_created_at_d22f14e09a       (user_id,entity_type,created_at DESC)
#  index_conversation_contexts_on_chat_id                 (chat_id)
#  index_conversation_contexts_on_chat_id_and_created_at  (chat_id,created_at DESC) WHERE (chat_id IS NOT NULL)
#  index_conversation_contexts_on_entity_data             (entity_data) USING gin
#  index_conversation_contexts_on_expires_at              (expires_at) WHERE (expires_at IS NOT NULL)
#  index_conversation_contexts_on_metadata                (metadata) USING gin
#  index_conversation_contexts_on_user_id                 (user_id)
#  index_conversation_contexts_on_user_id_and_created_at  (user_id,created_at DESC)
#
# Foreign Keys
#
#  fk_rails_...  (chat_id => chats.id)
#  fk_rails_...  (user_id => users.id)
#
require 'rails_helper'

RSpec.describe ConversationContext, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
