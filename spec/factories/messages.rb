FactoryBot.define do
  factory :message do
    chat { association :chat }
    role { :assistant }
    content { "This is a test message" }
    metadata { {} }

    trait :user do
      role { :user }
      user { association :user }
      content { "User message content" }
    end

    trait :assistant do
      role { :assistant }
      content { "Assistant response" }
    end

    trait :system do
      role { :system }
      content { "System message" }
    end

    trait :tool do
      role { :tool }
      content { "Tool response" }
    end

    trait :templated do
      template_type { "search_results" }
      content { nil }
      metadata { { template_data: { results: [], query: "test" } } }
    end

    trait :with_rag_sources do
      metadata { { rag_sources: [{ title: "Source 1", content: "Content" }] } }
    end

    trait :with_feedback do
      after(:create) do |message|
        message_user = create(:user)
        create(:message_feedback, message: message, user: message_user, rating: :helpful)
      end
    end
  end

  factory :message_feedback do
    message { association :message }
    user { association :user }
    chat { message.chat }
    rating { :helpful }
    helpfulness_score { 10 }

    trait :unhelpful do
      rating { :unhelpful }
      helpfulness_score { 3 }
    end

    trait :harmful do
      rating { :harmful }
      helpfulness_score { 0 }
    end

    trait :neutral do
      rating { :neutral }
      helpfulness_score { 5 }
    end
  end
end
