# == Schema Information
#
# Table name: organization_memberships
#
#  id              :uuid             not null, primary key
#  joined_at       :datetime         not null
#  metadata        :jsonb            not null
#  role            :integer          default("member"), not null
#  status          :integer          default("active"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#  user_id         :uuid             not null
#
# Indexes
#
#  index_organization_memberships_on_joined_at                    (joined_at)
#  index_organization_memberships_on_organization_id              (organization_id)
#  index_organization_memberships_on_organization_id_and_user_id  (organization_id,user_id) UNIQUE
#  index_organization_memberships_on_role                         (role)
#  index_organization_memberships_on_status                       (status)
#  index_organization_memberships_on_user_id                      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (user_id => users.id)
#
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
