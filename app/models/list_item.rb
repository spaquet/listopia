# app/models/list_item.rb
# == Schema Information
#
# Table name: list_items
#
#  id               :uuid             not null, primary key
#  completed        :boolean          default(FALSE)
#  completed_at     :datetime
#  description      :text
#  due_date         :datetime
#  item_type        :integer          default("task"), not null
#  metadata         :json
#  position         :integer          default(0)
#  priority         :integer          default("medium"), not null
#  reminder_at      :datetime
#  title            :string           not null
#  url              :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  assigned_user_id :uuid
#  list_id          :uuid             not null
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
#  index_list_items_on_list_id_and_priority            (list_id,priority)
#  index_list_items_on_position                        (position)
#  index_list_items_on_priority                        (priority)
#
# Foreign Keys
#
#  fk_rails_...  (assigned_user_id => users.id)
#  fk_rails_...  (list_id => lists.id)
#
class ListItem < ApplicationRecord
  # Associations
  belongs_to :list
  belongs_to :assigned_user, class_name: "User", optional: true

  # Validations
  validates :title, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: 1000 }
  validates :item_type, presence: true
  validates :priority, presence: true

  # Enums
  enum :item_type, {
    task: 0,
    note: 1,
    link: 2,
    file: 3,
    reminder: 4
  }, prefix: true

  enum :priority, {
    low: 0,
    medium: 1,
    high: 2,
    urgent: 3
  }, prefix: true

  # Scopes
  scope :completed, -> { where(completed: true) }
  scope :pending, -> { where(completed: false) }
  scope :assigned_to, ->(user) { where(assigned_user: user) }
  scope :by_priority, -> { order(:priority) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  before_save :set_completed_at

  # Methods

  # Toggle completion status
  def toggle_completion!
    update!(completed: !completed)
  end

  # Check if item is overdue (if due_date is set)
  def overdue?
    due_date.present? && due_date < Time.current && !completed?
  end

  # Check if user can edit this item
  def editable_by?(user)
    return false unless user

    list.collaboratable_by?(user) || assigned_user == user
  end

  private

  # Set completed_at timestamp when item is marked as completed
  def set_completed_at
    if completed_changed?
      self.completed_at = completed? ? Time.current : nil
    end
  end
end
