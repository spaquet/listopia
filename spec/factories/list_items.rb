# spec/factories/list_items.rb
# == Schema Information
#
# Table name: list_items
#
#  id                 :uuid             not null, primary key
#  completed          :boolean          default(FALSE)
#  completed_at       :datetime
#  description        :text
#  due_date           :datetime
#  item_type          :integer          default("task"), not null
#  metadata           :json
#  position           :integer          default(0)
#  priority           :integer          default("medium"), not null
#  reminder_at        :datetime
#  skip_notifications :boolean          default(FALSE), not null
#  title              :string           not null
#  url                :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  assigned_user_id   :uuid
#  list_id            :uuid             not null
#
# Indexes
#
#  index_list_items_on_assigned_user_id                (assigned_user_id)
#  index_list_items_on_assigned_user_id_and_completed  (assigned_user_id,completed)
#  index_list_items_on_completed                       (completed)
#  index_list_items_on_created_at                      (created_at)
#  index_list_items_on_due_date                        (due_date)
#  index_list_items_on_due_date_and_completed          (due_date,completed)
#  index_list_items_on_item_type                       (item_type)
#  index_list_items_on_list_id                         (list_id)
#  index_list_items_on_list_id_and_completed           (list_id,completed)
#  index_list_items_on_list_id_and_position            (list_id,position) UNIQUE
#  index_list_items_on_list_id_and_priority            (list_id,priority)
#  index_list_items_on_position                        (position)
#  index_list_items_on_priority                        (priority)
#  index_list_items_on_skip_notifications              (skip_notifications)
#
# Foreign Keys
#
#  fk_rails_...  (assigned_user_id => users.id)
#  fk_rails_...  (list_id => lists.id)
#
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
