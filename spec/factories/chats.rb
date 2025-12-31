# == Schema Information
#
# Table name: chats
#
#  id                    :uuid             not null, primary key
#  context               :json
#  conversation_state    :string           default("stable")
#  focused_resource_type :string
#  last_cleanup_at       :datetime
#  last_message_at       :datetime
#  last_stable_at        :datetime
#  metadata              :json
#  model_id_string       :string
#  status                :string           default("active")
#  title                 :string(255)
#  visibility            :string           default("private")
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  focused_resource_id   :uuid
#  model_id              :bigint
#  organization_id       :uuid
#  team_id               :uuid
#  user_id               :uuid             not null
#
# Indexes
#
#  index_chats_on_conversation_state                             (conversation_state)
#  index_chats_on_focused_resource_type_and_focused_resource_id  (focused_resource_type,focused_resource_id)
#  index_chats_on_last_message_at                                (last_message_at)
#  index_chats_on_last_stable_at                                 (last_stable_at)
#  index_chats_on_model_id                                       (model_id)
#  index_chats_on_organization_id                                (organization_id)
#  index_chats_on_organization_id_and_created_at                 (organization_id,created_at)
#  index_chats_on_organization_id_and_user_id                    (organization_id,user_id)
#  index_chats_on_status                                         (status)
#  index_chats_on_team_id                                        (team_id)
#  index_chats_on_team_id_and_user_id                            (team_id,user_id)
#  index_chats_on_user_id                                        (user_id)
#  index_chats_on_user_id_and_created_at                         (user_id,created_at)
#  index_chats_on_user_id_and_status                             (user_id,status)
#  index_chats_on_visibility                                     (visibility)
#
# Foreign Keys
#
#  fk_rails_...  (model_id => models.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (team_id => teams.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :chat do
    user { association :user }
    organization { association :organization, creator: user }
    title { "New Conversation" }
    status { :active }
    metadata { {} }

    trait :archived do
      status { :archived }
    end

    trait :deleted do
      status { :deleted }
    end

    trait :with_messages do
      after(:create) do |chat|
        create(:message, chat: chat, role: :user)
        create(:message, chat: chat, role: :assistant)
        create(:message, chat: chat, role: :user)
      end
    end

    trait :with_context do
      after(:create) do |chat|
        list = create(:list, user: chat.user, organization: chat.organization)
        chat.update(focused_resource: list)
      end
    end
  end
end
