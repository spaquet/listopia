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
