# app/models/list_item.rb
# == Schema Information
#
# Table name: list_items
#
#  id                  :uuid             not null, primary key
#  description         :text
#  due_date            :datetime
#  duration_days       :integer          default(0), not null
#  estimated_duration  :decimal(10, 2)   default(0.0), not null
#  item_type           :integer          default("task"), not null
#  metadata            :json
#  position            :integer          default(0)
#  priority            :integer          default("medium"), not null
#  recurrence_end_date :datetime
#  recurrence_rule     :string           default("none"), not null
#  reminder_at         :datetime
#  skip_notifications  :boolean          default(FALSE), not null
#  start_date          :datetime         not null
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
# app/models/list_item.rb
class ListItem < ApplicationRecord
  include Turbo::Broadcastable

  attr_accessor :skip_notifications, :previous_title_value

  # Associations
  belongs_to :list, counter_cache: true
  belongs_to :assigned_user, class_name: "User", optional: true
  belongs_to :board_column, optional: true

  has_many :time_entries, dependent: :destroy

  # Validations
  validates :title, presence: true, length: { maximum: 255 }
  validates :item_type, presence: true
  validates :priority, presence: true
  validates :status, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Enums
  enum :item_type, {
    # Work & Projects
    task: 0,          # General to-do items ✓
    milestone: 1,     # Key achievements 🎯
    feature: 2,       # Product features 🚀
    bug: 3,           # Issues to fix 🐛
    decision: 4,      # Choices to make 🤔
    meeting: 5,       # Scheduled meetings 📅
    reminder: 6,      # Time-based alerts ⏰
    note: 7,          # Information capture 📝
    reference: 8,     # Links and resources 🔗

    # Personal Life Management
    habit: 9,         # Recurring personal development 🔄
    health: 10,       # Fitness, medical, wellness 🏃‍♀️
    learning: 11,     # Books, courses, skills 📚
    travel: 12,       # Trips and vacation planning ✈️
    shopping: 13,     # Purchases and errands 🛒
    home: 14,         # Household tasks and improvements 🏠
    finance: 15,      # Budget, bills, investments 💰
    social: 16,       # Events, gatherings, relationships 👥
    entertainment: 17 # Movies, shows, games, hobbies 🎬
  }, prefix: true

  enum :priority, {
    low: 0,
    medium: 1,
    high: 2,
    urgent: 3
  }, prefix: true

  enum :status, {
    pending: 0,
    in_progress: 1,
    completed: 2
  }, prefix: true

  # Scopes
  scope :completed, -> { where(status: :completed) }
  scope :pending, -> { where(status: :pending) }
  scope :in_progress, -> { where(status: :in_progress) }
  scope :assigned_to, ->(user) { where(assigned_user: user) }
  scope :by_priority, -> { order(priority: :desc) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks - Use after_commit to avoid issues during transactions
  before_destroy :notify_item_destroyed
  before_save :track_status_change, :track_title_change
  after_commit :notify_item_created, on: :create
  after_commit :notify_item_updated, on: :update
  after_create :assign_default_board_column

  # Methods

  # Toggle completion status
  def toggle_completion!(skip_notifications: false)
    self.skip_notifications = skip_notifications
    new_status = status_completed? ? :pending : :completed
    update!(status: new_status, status_changed_at: Time.current)
  end

  def overdue?
    due_date.present? && due_date < Time.current && !status_completed?
  end

  # Check if user can edit this item
  def editable_by?(user)
    return false unless user

    list.collaboratable_by?(user) || assigned_user == user
  end

  private

  # Track status changes for notifications
  def track_status_change
    if status_changed?
      @previous_status_value = status_was
      self.status_changed_at = Time.current
    end
  end

  def track_title_change
    if title_changed?
      self.previous_title_value = title_was
    end
  end

  # Use NotificationService for all notifications to ensure consistency
  def notify_item_created
    return if skip_notifications || !Current.user

    NotificationService.new(Current.user)
                      .notify_item_activity(self, "created")
  end

  def notify_item_updated
    return if skip_notifications || !Current.user

    if @previous_status_value && @previous_status_value != status
      # Notify about status changes
      action = case status
      when "completed"
                 "completed"
      when "in_progress"
                 "started"
      when "pending"
                 "reopened"
      else
                 "updated"
      end

      NotificationService.new(Current.user)
                        .notify_item_activity(self, action, previous_title_value)
    elsif saved_changes.except("updated_at", "status_changed_at").any?
      NotificationService.new(Current.user)
                        .notify_item_activity(self, "updated", previous_title_value)
    end
  end

  # Notify when item is destroyed - check if list still exists
  def notify_item_destroyed
    return if skip_notifications || !Current.user

    # Don't send notifications if the list is being destroyed
    # (which would cascade destroy items)
    return if list.nil? || list.destroyed? || list.marked_for_destruction?

    NotificationService.new(Current.user)
                      .notify_item_activity(self, "deleted")
  end

  # Assign default board column after creation
  def assign_default_board_column
    return if board_column.present?

    default_column = list.board_columns.find_by(name: "To Do")
    update_column(:board_column_id, default_column&.id) if default_column
  end
end
