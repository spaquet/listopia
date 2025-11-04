# spec/factories/sessions.rb
# == Schema Information
#
# Table name: sessions
#
#  id               :uuid             not null, primary key
#  expires_at       :datetime         not null
#  ip_address       :string
#  last_accessed_at :datetime
#  session_token    :string           not null
#  user_agent       :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  user_id          :uuid             not null
#
# Indexes
#
#  index_sessions_on_expires_at              (expires_at)
#  index_sessions_on_session_token           (session_token) UNIQUE
#  index_sessions_on_user_id                 (user_id)
#  index_sessions_on_user_id_and_expires_at  (user_id,expires_at)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
# FactoryBot.define do
#   factory :session do
#     sequence(:session_token) { |n| SecureRandom.urlsafe_base64(32) }
#     ip_address { "192.168.1.1" }
#     user_agent { "Mozilla/5.0 (X11; Linux x86_64)" }
#     expires_at { 30.days.from_now }
#     association :user
#   end
# end
FactoryBot.define do
  factory :session do
    association :user

    # Generate session token explicitly
    sequence(:session_token) { SecureRandom.urlsafe_base64(32) }

    # Default expires_at to 30 days from now
    # (model's before_create callback sets this, but we set it here as well)
    expires_at { 30.days.from_now }

    # Set other attributes with sensible defaults
    ip_address { "192.168.1.1" }
    user_agent { "Mozilla/5.0 (X11; Linux x86_64)" }
    # last_accessed_at is intentionally not set (defaults to nil)

    # Trait for expired sessions - overrides expires_at AFTER create
    trait :expired do
      after(:create) do |session|
        session.update_column(:expires_at, 1.day.ago)
      end
    end

    trait :expiring_soon do
      after(:create) do |session|
        session.update_column(:expires_at, 1.hour.from_now)
      end
    end

    trait :expiring_in_days do
      after(:create) do |session|
        session.update_column(:expires_at, 15.days.from_now)
      end
    end
  end
end
