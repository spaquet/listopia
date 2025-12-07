# spec/factories/list_items.rb
# == Schema Information
#
# Table name: list_items
#
#  id                  :uuid             not null, primary key
#  completed_at        :datetime
#  description         :text
#  due_date            :datetime
#  duration_days       :integer
#  estimated_duration  :decimal(10, 2)   default(0.0), not null
#  item_type           :integer          default("task"), not null
#  metadata            :json
#  position            :integer          default(0)
#  priority            :integer          default("medium"), not null
#  recurrence_end_date :datetime
#  recurrence_rule     :string           default("none"), not null
#  reminder_at         :datetime
#  skip_notifications  :boolean          default(FALSE), not null
#  start_date          :datetime
#  status              :integer          default("pending"), not null
#  status_changed_at   :datetime
#  title               :string           not null
#  total_tracked_time  :decimal(10, 2)   default(0.0), not null
#  url                 :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  assigned_user_id    :uuid
#  board_column_id     :uuid
#  list_id             :uuid             not null
#
# Indexes
#
#  index_list_items_on_assigned_user_id             (assigned_user_id)
#  index_list_items_on_assigned_user_id_and_status  (assigned_user_id,status)
#  index_list_items_on_board_column_id              (board_column_id)
#  index_list_items_on_completed_at                 (completed_at)
#  index_list_items_on_created_at                   (created_at)
#  index_list_items_on_due_date                     (due_date)
#  index_list_items_on_due_date_and_status          (due_date,status)
#  index_list_items_on_item_type                    (item_type)
#  index_list_items_on_list_id                      (list_id)
#  index_list_items_on_list_id_and_position         (list_id,position) UNIQUE
#  index_list_items_on_list_id_and_priority         (list_id,priority)
#  index_list_items_on_list_id_and_status           (list_id,status)
#  index_list_items_on_position                     (position)
#  index_list_items_on_priority                     (priority)
#  index_list_items_on_skip_notifications           (skip_notifications)
#  index_list_items_on_status                       (status)
#
# Foreign Keys
#
#  fk_rails_...  (assigned_user_id => users.id)
#  fk_rails_...  (board_column_id => board_columns.id)
#  fk_rails_...  (list_id => lists.id)
#
FactoryBot.define do
  factory :list_item do
    sequence(:title) { |n| "Task #{n}" }
    description { Faker::Lorem.paragraph(sentence_count: 3) }
    item_type { :task }
    priority { :medium }
    status { :pending }
    sequence(:position) { |n| n }
    start_date { Time.current }
    duration_days { 0 }
    estimated_duration { 0.0 }
    total_tracked_time { 0.0 }
    recurrence_rule { "none" }
    skip_notifications { false }

    association :list, strategy: :build

    # Work & Project Item Types
    trait :task do
      item_type { :task }
      sequence(:title) { |n| "Task #{n}" }
    end

    trait :milestone do
      item_type { :milestone }
      sequence(:title) { |n| "Milestone #{n}" }
    end

    trait :feature do
      item_type { :feature }
      sequence(:title) { |n| "Feature #{n}" }
    end

    trait :bug do
      item_type { :bug }
      sequence(:title) { |n| "Bug #{n}" }
    end

    trait :decision do
      item_type { :decision }
      sequence(:title) { |n| "Decision #{n}" }
    end

    trait :meeting do
      item_type { :meeting }
      sequence(:title) { |n| "Meeting #{n}" }
    end

    trait :reminder do
      item_type { :reminder }
      reminder_at { 2.days.from_now }
      sequence(:title) { |n| "Reminder #{n}" }
    end

    trait :note do
      item_type { :note }
      sequence(:title) { |n| "Note #{n}" }
    end

    trait :reference do
      item_type { :reference }
      url { Faker::Internet.url }
      sequence(:title) { |n| "Reference #{n}" }
    end

    # Personal Life Item Types
    trait :habit do
      item_type { :habit }
      sequence(:title) { |n| "Habit #{n}" }
    end

    trait :health do
      item_type { :health }
      sequence(:title) { |n| "Health #{n}" }
    end

    trait :learning do
      item_type { :learning }
      sequence(:title) { |n| "Learning #{n}" }
    end

    trait :travel do
      item_type { :travel }
      sequence(:title) { |n| "Travel #{n}" }
    end

    trait :shopping do
      item_type { :shopping }
      sequence(:title) { |n| "Shopping #{n}" }
    end

    trait :home do
      item_type { :home }
      sequence(:title) { |n| "Home Task #{n}" }
    end

    trait :finance do
      item_type { :finance }
      sequence(:title) { |n| "Finance #{n}" }
    end

    trait :social do
      item_type { :social }
      sequence(:title) { |n| "Social Event #{n}" }
    end

    trait :entertainment do
      item_type { :entertainment }
      sequence(:title) { |n| "Entertainment #{n}" }
    end

    # Status Traits
    trait :pending do
      status { :pending }
      status_changed_at { nil }
    end

    trait :in_progress do
      status { :in_progress }
      status_changed_at { 1.day.ago }
    end

    trait :completed do
      status { :completed }
      status_changed_at { Time.current }
    end

    # Priority Traits
    trait :low_priority do
      priority { :low }
    end

    trait :high_priority do
      priority { :high }
    end

    trait :urgent_priority do
      priority { :urgent }
    end

    # Due Date Traits
    trait :with_due_date do
      due_date { 5.days.from_now }
    end

    trait :overdue do
      due_date { 3.days.ago }
      status { :pending }
    end

    trait :due_soon do
      due_date { 2.days.from_now }
    end

    # Assignment Traits
    trait :assigned do
      association :assigned_user, factory: :user
    end

    trait :assigned_to do
      transient do
        assigned_user { association :user }
      end

      after(:build) do |item, evaluator|
        item.assigned_user = evaluator.assigned_user
      end
    end

    # Recurrence Traits
    trait :daily_recurring do
      recurrence_rule { "daily" }
      recurrence_end_date { 30.days.from_now }
    end

    trait :weekly_recurring do
      recurrence_rule { "weekly" }
      recurrence_end_date { 60.days.from_now }
    end

    # Tracking Traits
    trait :with_time_logged do
      total_tracked_time { 5.5 }
      estimated_duration { 8.0 }
    end

    trait :with_metadata do
      metadata { { "custom_field" => "value", "tags" => [ "important", "bug" ] } }
    end

    # Complex Traits (combine multiple)
    trait :urgent_overdue_task do
      priority { :urgent }
      status { :pending }
      due_date { 5.days.ago }
    end

    trait :completed_with_time_tracked do
      status { :completed }
      total_tracked_time { 8.0 }
      estimated_duration { 8.0 }
      status_changed_at { 2.days.ago }
    end

    trait :assigned_high_priority_due_soon do
      association :assigned_user, factory: :user
      priority { :high }
      due_date { 2.days.from_now }
      status { :in_progress }
    end

    # URL Traits
    trait :with_url do
      url { Faker::Internet.url }
    end

    trait :with_https_url do
      url { "https://example.com/page" }
    end

    trait :with_http_url do
      url { "http://example.com/page" }
    end

    trait :with_complex_url do
      url { "https://github.com/rails/rails/issues?state=open&label=bug#comments" }
    end

    trait :with_relative_url do
      url { "/internal/documentation/page" }
    end

    trait :with_unschemed_url do
      url { "example.com" }
    end
  end
end
