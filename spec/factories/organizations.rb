# == Schema Information
#
# Table name: organizations
#
#  id            :uuid             not null, primary key
#  metadata      :jsonb            not null
#  name          :string           not null
#  size          :integer          default("small"), not null
#  slug          :string           not null
#  status        :integer          default("active"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  created_by_id :uuid             not null
#
# Indexes
#
#  index_organizations_on_created_at     (created_at)
#  index_organizations_on_created_by_id  (created_by_id)
#  index_organizations_on_size           (size)
#  index_organizations_on_slug           (slug) UNIQUE
#  index_organizations_on_status         (status)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#
FactoryBot.define do
  factory :organization do
    sequence(:name) { |n| "Organization #{n}" }
    sequence(:slug) { |n| "org-#{n}" }
    size { :small }
    status { :active }
    creator { association :user }

    trait :medium do
      size { :medium }
    end

    trait :large do
      size { :large }
    end

    trait :enterprise do
      size { :enterprise }
    end

    trait :suspended do
      status { :suspended }
    end

    trait :deleted do
      status { :deleted }
    end

    trait :with_members do
      after(:create) do |organization|
        3.times do
          user = create(:user)
          create(:organization_membership, organization: organization, user: user, role: :member)
        end
      end
    end

    trait :with_teams do
      after(:create) do |organization|
        2.times do
          create(:team, organization: organization, created_by: organization.creator)
        end
      end
    end

    trait :with_lists do
      after(:create) do |organization|
        3.times do
          create(:list, owner: organization.creator, organization: organization)
        end
      end
    end
  end
end
