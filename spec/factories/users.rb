# spec/factories/users.rb
# == Schema Information
#
# Table name: users
#
#  id                       :uuid             not null, primary key
#  account_metadata         :jsonb
#  admin_notes              :text
#  avatar_url               :string
#  bio                      :text
#  deactivated_at           :datetime
#  deactivated_reason       :text
#  discarded_at             :datetime
#  email                    :string           not null
#  email_verification_token :string
#  email_verified_at        :datetime
#  invited_by_admin         :boolean          default(FALSE)
#  last_sign_in_at          :datetime
#  last_sign_in_ip          :string
#  locale                   :string(10)       default("en"), not null
#  name                     :string           not null
#  password_digest          :string           not null
#  provider                 :string
#  sign_in_count            :integer          default(0), not null
#  status                   :string           default("active"), not null
#  suspended_at             :datetime
#  suspended_reason         :text
#  timezone                 :string(50)       default("UTC"), not null
#  uid                      :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  current_organization_id  :uuid
#  suspended_by_id          :uuid
#
# Indexes
#
#  index_users_on_account_metadata          (account_metadata) USING gin
#  index_users_on_current_organization_id   (current_organization_id)
#  index_users_on_deactivated_at            (deactivated_at)
#  index_users_on_discarded_at              (discarded_at)
#  index_users_on_email                     (email) UNIQUE
#  index_users_on_email_verification_token  (email_verification_token) UNIQUE
#  index_users_on_invited_by_admin          (invited_by_admin)
#  index_users_on_last_sign_in_at           (last_sign_in_at)
#  index_users_on_locale                    (locale)
#  index_users_on_provider_and_uid          (provider,uid) UNIQUE
#  index_users_on_status                    (status)
#  index_users_on_suspended_at              (suspended_at)
#  index_users_on_timezone                  (timezone)
#
# Foreign Keys
#
#  fk_rails_...  (suspended_by_id => users.id)
#
FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    sequence(:name) { |n| "User #{n}" }
    password { "password123" }
    password_confirmation { password }
    locale { "en" }
    timezone { "UTC" }
    status { "active" }

    # Traits for different user states
    trait :verified do
      email_verified_at { 1.day.ago }
    end

    trait :unverified do
      email_verified_at { nil }
    end

    trait :admin do
      verified
      after(:create) { |user| user.add_role(:admin) }
    end

    trait :suspended do
      verified
      status { "suspended" }
      suspended_at { Time.current }
      association :suspended_by, factory: :user
    end

    trait :deactivated do
      verified
      status { "deactivated" }
      deactivated_at { Time.current }
      deactivated_reason { "User requested deactivation" }
    end

    trait :with_bio do
      bio { Faker::Lorem.paragraph }
    end

    trait :with_avatar do
      avatar_url { "https://example.com/avatar.jpg" }
    end

    trait :with_admin_notes do
      admin_notes { Faker::Lorem.paragraph }
    end
  end
end
