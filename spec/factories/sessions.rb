# spec/factories/sessions.rb
FactoryBot.define do
  factory :session do
    ip_address { Faker::Internet.ip_v4_address }
    user_agent { Faker::Internet.user_agent }
    expires_at { 30.days.from_now }

    association :user, factory: :user, strategy: :build

    # Traits for different session states
    trait :expired do
      expires_at { 1.hour.ago }
    end

    trait :expiring_soon do
      expires_at { 1.hour.from_now }
    end

    trait :long_lived do
      expires_at { 90.days.from_now }
    end

    trait :with_last_access do
      last_accessed_at { 1.hour.ago }
    end

    # Traits for different devices/contexts
    trait :mobile do
      user_agent { 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_7_1 like Mac OS X) AppleWebKit/605.1.15' }
    end

    trait :desktop do
      user_agent { 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36' }
    end

    trait :tablet do
      user_agent { 'Mozilla/5.0 (iPad; CPU OS 14_7_1 like Mac OS X) AppleWebKit/605.1.15' }
    end
  end
end
