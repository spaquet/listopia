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
  # Track changes for notifications
  attribute :previous_title_value
  attribute :skip_notifications, :boolean, default: false

  # Callbacks
  before_update :track_title_change
  after_create :notify_item_created
  after_update :notify_item_updated
  after_destroy :notify_item_destroyed

  # Notification Callbacks
  after_commit :notify_item_created, on: :create
  after_commit :notify_item_updated, on: :update
  before_destroy :notify_item_deleted

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
  # Core Planning Types
  task: 0,          # Basic actionable item ✓
  goal: 1,          # Objectives and targets 🎯
  milestone: 2,     # Key deadlines and achievements 🏆
  action_item: 3,   # Specific next actions ⚡
  waiting_for: 4,   # Blocked items awaiting others ⏳
  reminder: 5,      # Time-based notifications ⏰

  # Knowledge & Ideas
  idea: 6,          # Brainstorming and concepts 💡
  note: 7,          # Information and documentation 📝
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

  # Track completion change for notifications
  def toggle_completion!(skip_notifications: false)
    self.skip_notifications = skip_notifications
    update!(completed: !completed)
  end


  private

  # Set completed_at timestamp when item is marked as completed
  def set_completed_at
    if completed_changed?
      self.completed_at = completed? ? Time.current : nil
    end
  end

  def track_title_change
    if title_changed?
      self.previous_title_value = title_was
    end
  end

  def notify_item_created
    return if skip_notifications || !Current.user

    NotificationService.new(Current.user)
                      .notify_item_activity(self, "created")
  end

  def notify_item_updated
    return if skip_notifications || !Current.user

    if saved_change_to_completed?
      action = completed? ? "completed" : "uncompleted"
      NotificationService.new(Current.user)
                        .notify_item_activity(self, action, previous_title_value)
    elsif saved_changes.except("updated_at", "completed_at").any?
      NotificationService.new(Current.user)
                        .notify_item_activity(self, "updated", previous_title_value)
    end
  end

  # Notify when item is destroyed
  def notify_item_destroyed
    return if skip_notifications || !Current.user

    NotificationService.new(Current.user)
                      .notify_item_activity(self, "deleted")
  end

  # Notify collaborators of item activity
  def notify_item_created
    notify_item_activity("created")
  end

  # Notify collaborators of item update
  def notify_item_updated
    notify_item_activity("updated")
  end

  # Notify collaborators of item deletion
  def notify_item_deleted
    notify_item_activity("deleted")
  end

  # Notify collaborators of item activity
  def notify_item_activity(action)
    return unless Current.user
    recipients = list.collaborators.where.not(id: Current.user.id)
    ListItemActivityNotifier.with(
      actor_id: Current.user.id,
      list_id: list.id,
      item_title: title,
      action: action
    ).deliver_to_enabled_users(recipients)
  end
end
