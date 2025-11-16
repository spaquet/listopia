FactoryBot.define do
  factory :team_membership do
    team { association :team }
    user { association :user }
    organization_membership { association :organization_membership, organization: team.organization, user: user }
    role { :member }
    joined_at { Time.current }

    trait :lead do
      role { :lead }
    end

    trait :admin do
      role { :admin }
    end
  end
end
