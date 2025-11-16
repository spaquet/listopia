# == Schema Information
#
# Table name: teams
#
#  id              :uuid             not null, primary key
#  metadata        :jsonb            not null
#  name            :string           not null
#  slug            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  created_by_id   :uuid             not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_teams_on_created_at                (created_at)
#  index_teams_on_created_by_id             (created_by_id)
#  index_teams_on_organization_id           (organization_id)
#  index_teams_on_organization_id_and_slug  (organization_id,slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (organization_id => organizations.id)
#
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
