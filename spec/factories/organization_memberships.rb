FactoryBot.define do
  factory :organization_membership do
    organization { association :organization }
    user { association :user }
    role { :member }
    status { :active }
    joined_at { Time.current }

    trait :admin do
      role { :admin }
    end

    trait :owner do
      role { :owner }
    end

    trait :pending do
      status { :pending }
    end

    trait :suspended do
      status { :suspended }
    end

    trait :revoked do
      status { :revoked }
    end
  end
end
