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
FactoryBot.define do
  factory :conversation_checkpoint do
    
  end
end
