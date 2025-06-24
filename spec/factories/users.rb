# spec/factories/users.rb
FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    sequence(:name) { |n| "User #{n}" }
    password { "password123" }
    password_confirmation { password }

    # Traits for different user states
    trait :verified do
      email_verified_at { 1.day.ago }
    end

    trait :unverified do
      email_verified_at { nil }
    end

    trait :with_bio do
      bio { Faker::Lorem.paragraph }
    end

    trait :with_avatar do
      avatar_url { "https://example.com/avatar.jpg" }
    end
  end
end
