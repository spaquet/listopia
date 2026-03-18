FactoryBot.define do
  factory :connectors_account, class: "Connectors::Account" do
    user { create(:user) }
    organization { create(:organization, creator: user) }
    provider { "google_calendar" }
    provider_uid { Faker::Alphanumeric.alphanumeric(number: 20) }
    display_name { "Test Account" }
    email { Faker::Internet.email }
    access_token_encrypted { nil }
    refresh_token_encrypted { nil }
    token_expires_at { 1.hour.from_now }
    token_scope { "calendar" }
    status { "active" }
    last_sync_at { nil }
    last_error { nil }
    error_count { 0 }
    metadata { {} }

    trait :with_tokens do
      transient do
        access_token { Faker::Alphanumeric.alphanumeric(number: 50) }
        refresh_token { Faker::Alphanumeric.alphanumeric(number: 50) }
      end

      after(:build) do |account, evaluator|
        secret = Rails.application.credentials.dig(:connector_tokens, :secret)
        secret = Rails.application.key_generator.generate_key("connector_tokens.secret", 32) if secret.blank?
        encryptor = ActiveSupport::MessageEncryptor.new(secret)
        account.access_token_encrypted = encryptor.encrypt_and_sign(evaluator.access_token)
        account.refresh_token_encrypted = encryptor.encrypt_and_sign(evaluator.refresh_token)
      end
    end

    trait :expired_token do
      token_expires_at { 1.hour.ago }
    end

    trait :paused do
      status { "paused" }
    end

    trait :errored do
      status { "errored" }
      last_error { "Connection failed" }
      error_count { 5 }
    end
  end

  factory :connectors_setting, class: "Connectors::Setting" do
    account { create(:connectors_account) }
    key { "sync_direction" }
    value { "both" }
  end

  factory :connectors_sync_log, class: "Connectors::SyncLog" do
    account { create(:connectors_account) }
    operation { "calendar_sync" }
    status { "success" }
    records_processed { 10 }
    records_created { 5 }
    records_updated { 3 }
    records_failed { 0 }
    started_at { 5.minutes.ago }
    completed_at { 4.minutes.ago }

    trait :in_progress do
      status { "in_progress" }
      completed_at { nil }
    end

    trait :failed do
      status { "failure" }
      error_message { "API error" }
    end
  end

  factory :connectors_event_mapping, class: "Connectors::EventMapping" do
    account { create(:connectors_account) }
    external_id { Faker::Alphanumeric.alphanumeric(number: 20) }
    external_type { "calendar_event" }
    local_type { "ListItem" }
    local_id { SecureRandom.uuid }
    sync_direction { "both" }
    last_synced_at { Time.current }
    external_etag { Faker::Alphanumeric.alphanumeric(number: 32) }
    metadata { {} }
  end
end
