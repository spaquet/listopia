# == Schema Information
#
# Table name: messages
#
#  id                    :uuid             not null, primary key
#  blocked               :boolean          default(FALSE)
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
#  template_type         :string
#  token_count           :integer
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  chat_id               :uuid             not null
#  model_id              :bigint
#  organization_id       :uuid
#  tool_call_id          :uuid
#  user_id               :uuid
#
# Indexes
#
#  index_messages_on_blocked                      (blocked)
#  index_messages_on_chat_and_tool_call_id        (chat_id,tool_call_id) WHERE (tool_call_id IS NOT NULL)
#  index_messages_on_chat_id                      (chat_id)
#  index_messages_on_chat_id_and_created_at       (chat_id,created_at)
#  index_messages_on_llm_provider                 (llm_provider)
#  index_messages_on_llm_provider_and_llm_model   (llm_provider,llm_model)
#  index_messages_on_message_type                 (message_type)
#  index_messages_on_model_id                     (model_id)
#  index_messages_on_model_id_string              (model_id_string)
#  index_messages_on_organization_id              (organization_id)
#  index_messages_on_organization_id_and_user_id  (organization_id,user_id)
#  index_messages_on_role                         (role)
#  index_messages_on_template_type                (template_type)
#  index_messages_on_tool_call_id                 (tool_call_id)
#  index_messages_on_user_id                      (user_id)
#  index_messages_on_user_id_and_created_at       (user_id,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (chat_id => chats.id)
#  fk_rails_...  (model_id => models.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (tool_call_id => tool_calls.id)
#  fk_rails_...  (user_id => users.id)
#
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
      metadata { { rag_sources: [ { title: "Source 1", content: "Content" } ] } }
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
