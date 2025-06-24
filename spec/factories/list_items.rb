# spec/factories/list_items.rb
FactoryBot.define do
  factory :list_item do
    sequence(:title) { |n| "Task #{n}" }
    description { Faker::Lorem.paragraph }
    item_type { :task }
    priority { :medium }
    completed { false }
    position { 0 }

    association :list, strategy: :build

    # Traits for different item types
    trait :task do
      item_type { :task }
    end

    trait :note do
      item_type { :note }
    end

    trait :link do
      item_type { :link }
      url { Faker::Internet.url }
    end

    trait :file do
      item_type { :file }
    end

    trait :reminder do
      item_type { :reminder }
      reminder_at { 1.hour.from_now }
    end

    # Traits for different priorities
    trait :low_priority do
      priority { :low }
    end

    trait :medium_priority do
      priority { :medium }
    end

    trait :high_priority do
      priority { :high }
    end

    trait :urgent_priority do
      priority { :urgent }
    end

    # Traits for completion status
    trait :completed do
      completed { true }
      completed_at { 1.hour.ago }
    end

    trait :pending do
      completed { false }
      completed_at { nil }
    end

    # Traits for due dates
    trait :due_today do
      due_date { Date.current.end_of_day }
    end

    trait :due_tomorrow do
      due_date { 1.day.from_now.end_of_day }
    end

    trait :overdue do
      due_date { 1.day.ago }
    end

    trait :with_assignment do
      association :assigned_user, factory: :user, strategy: :build
    end
  end
end
