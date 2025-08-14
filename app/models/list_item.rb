# app/models/list_item.rb
# == Schema Information
#
# Table name: list_items
#
#  id                  :uuid             not null, primary key
#  completed           :boolean          default(FALSE)
#  completed_at        :datetime
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
#  index_list_items_on_assigned_user_id                (assigned_user_id)
#  index_list_items_on_assigned_user_id_and_completed  (assigned_user_id,completed)
#  index_list_items_on_board_column_id                 (board_column_id)
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
#  fk_rails_...  (board_column_id => board_columns.id)
#  fk_rails_...  (list_id => lists.id)
#
class ListItem < ApplicationRecord
  # Track changes for notifications
  attribute :previous_title_value
  attribute :skip_notifications, :boolean, default: false

  # Associations
  belongs_to :list, counter_cache: true
  belongs_to :assigned_user, class_name: "User", optional: true

  has_many :time_entries, dependent: :destroy
  has_many :collaborators, as: :collaboratable, dependent: :destroy
  has_many :collaborator_users, through: :collaborators, source: :user
  has_many :invitations, as: :invitable, dependent: :destroy
  has_many :comments, as: :commentable, dependent: :destroy
  belongs_to :board_column, optional: true
  has_many :parent_relationships, as: :parent, class_name: "Relationship", dependent: :destroy
  has_many :child_relationships, as: :child, class_name: "Relationship", dependent: :destroy
  has_many :children, through: :parent_relationships, source: :child, source_type: [ "ListItem", "List" ]
  has_many :parents, through: :child_relationships, source: :parent, source_type: [ "ListItem", "List" ]
  has_many :dependencies, -> { where(relationship_type: :dependency_finish_to_start) }, as: :child, class_name: "Relationship", dependent: :destroy
  has_many :dependents, -> { where(relationship_type: :dependency_finish_to_start) }, as: :parent, class_name: "Relationship", dependent: :destroy


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
  before_destroy :notify_item_destroyed
  before_save :set_completed_at
  before_update :track_title_change
  after_commit :notify_item_created, on: :create
  after_commit :notify_item_updated, on: :update
  after_create :assign_default_board_column
  after_create :track_creation_context
  after_update :track_update_context, if: :saved_changes?


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

  def track_creation_context
    if Current.user
      ConversationContext.track_action(
        user: Current.user,
        action: "item_added",
        entity: self,
        metadata: {
          list_id: list_id,
          priority: priority,
          auto_tracked: true
        }
      )
    end
  end

  def track_update_context
    if Current.user
      action = if saved_change_to_completed? && completed?
        "item_completed"
      elsif saved_change_to_assigned_user_id?
        "item_assigned"
      else
        "item_updated"
      end

      ConversationContext.track_action(
        user: Current.user,
        action: action,
        entity: self,
        metadata: {
          list_id: list_id,
          changes: saved_changes.keys,
          auto_tracked: true
        }
      )
    end
  end

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

  # Assign default board column after creation
  def assign_default_board_column
    update(board_column: list.board_columns.find_by(name: "To Do"))
  end
end
