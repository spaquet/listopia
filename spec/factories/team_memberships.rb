# == Schema Information
#
# Table name: team_memberships
#
#  id                         :uuid             not null, primary key
#  joined_at                  :datetime         not null
#  metadata                   :jsonb            not null
#  role                       :integer          default("member"), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  organization_membership_id :uuid             not null
#  team_id                    :uuid             not null
#  user_id                    :uuid             not null
#
# Indexes
#
#  index_team_memberships_on_joined_at                   (joined_at)
#  index_team_memberships_on_organization_membership_id  (organization_membership_id)
#  index_team_memberships_on_role                        (role)
#  index_team_memberships_on_team_id                     (team_id)
#  index_team_memberships_on_team_id_and_user_id         (team_id,user_id) UNIQUE
#  index_team_memberships_on_user_id                     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_membership_id => organization_memberships.id)
#  fk_rails_...  (team_id => teams.id)
#  fk_rails_...  (user_id => users.id)
#
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
