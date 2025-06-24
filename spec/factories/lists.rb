# spec/factories/lists.rb
FactoryBot.define do
  factory :list do
    sequence(:title) { |n| "My List #{n}" }
    description { Faker::Lorem.sentence }
    status { :active }
    color_theme { 'blue' }
    is_public { false }

    association :owner, factory: :user, strategy: :build

    # Traits for different list states
    trait :draft do
      status { :draft }
    end

    trait :active do
      status { :active }
    end

    trait :completed do
      status { :completed }
    end

    trait :archived do
      status { :archived }
    end

    trait :public do
      is_public { true }
      public_slug { SecureRandom.urlsafe_base64(8) }
    end

    trait :with_items do
      after(:create) do |list|
        create_list(:list_item, 3, list: list)
      end
    end

    trait :with_completed_items do
      after(:create) do |list|
        create_list(:list_item, 2, :completed, list: list)
        create_list(:list_item, 1, list: list)
      end
    end
  end
end
