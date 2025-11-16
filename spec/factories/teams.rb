FactoryBot.define do
  factory :team do
    organization { association :organization }
    sequence(:name) { |n| "Team #{n}" }
    sequence(:slug) { |n| "team-#{n}" }
    created_by { association :user }

    trait :with_members do
      after(:create) do |team|
        3.times do
          user = create(:user)
          org_membership = create(:organization_membership, organization: team.organization, user: user)
          create(:team_membership, team: team, user: user, organization_membership: org_membership, role: :member)
        end
      end
    end

    trait :with_admin do
      after(:create) do |team|
        user = create(:user)
        org_membership = create(:organization_membership, organization: team.organization, user: user, role: :admin)
        create(:team_membership, team: team, user: user, organization_membership: org_membership, role: :admin)
      end
    end

    trait :with_lists do
      after(:create) do |team|
        2.times do
          create(:list, team: team, organization: team.organization, owner: team.created_by)
        end
      end
    end
  end
end
