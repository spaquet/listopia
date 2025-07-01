# app/models/list_item.rb
class ListItem < ApplicationRecord
  # Track changes for notifications
  attribute :previous_title_value
  attribute :skip_notifications, :boolean, default: false

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

  # Callbacks - Use after_commit to avoid issues during transactions
  before_save :set_completed_at
  before_update :track_title_change
  after_commit :notify_item_created, on: :create
  after_commit :notify_item_updated, on: :update
  before_destroy :notify_item_destroyed

  # Methods

  # Toggle completion status
  def toggle_completion!
    update!(completed: !completed)
  end

  # Toggle completion with optional notification skipping
  def toggle_completion!(skip_notifications: false)
    self.skip_notifications = skip_notifications
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

    if saved_change_to_completed?
      action = completed? ? "completed" : "uncompleted"
      NotificationService.new(Current.user)
                        .notify_item_activity(self, action, previous_title_value)
    elsif saved_changes.except("updated_at", "completed_at").any?
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
end
