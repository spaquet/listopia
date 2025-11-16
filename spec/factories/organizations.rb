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
