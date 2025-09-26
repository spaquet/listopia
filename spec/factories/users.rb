# spec/factories/users.rb
# == Schema Information
#
# Table name: users
#
#  id                       :uuid             not null, primary key
#  avatar_url               :string
#  bio                      :text
#  email                    :string           not null
#  email_verification_token :string
#  email_verified_at        :datetime
#  locale                   :string(10)       default("en"), not null
#  name                     :string           not null
#  password_digest          :string           not null
#  provider                 :string
#  timezone                 :string(50)       default("UTC"), not null
#  uid                      :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
# Indexes
#
#  index_users_on_email                     (email) UNIQUE
#  index_users_on_email_verification_token  (email_verification_token) UNIQUE
#  index_users_on_locale                    (locale)
#  index_users_on_provider_and_uid          (provider,uid) UNIQUE
#  index_users_on_timezone                  (timezone)
#
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
