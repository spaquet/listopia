# spec/factories/list_collaborations.rb
FactoryBot.define do
  factory :list_collaboration do
    permission { :read }

    association :list, strategy: :build
    association :user, strategy: :build

    # Traits for different permissions
    trait :read_permission do
      permission { :read }
    end

    trait :collaborate_permission do
      permission { :collaborate }
    end

    # Trait for pending invitation (no user, only email)
    trait :pending do
      user { nil }
      sequence(:email) { |n| "invite#{n}@example.com" }
      invitation_token { SecureRandom.urlsafe_base64(32) }
      invitation_sent_at { Time.current }
    end

    # Trait for accepted invitation
    trait :accepted do
      invitation_accepted_at { Time.current }
    end
  end
end
