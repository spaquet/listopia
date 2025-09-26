# app/models/list.rb
class List < ApplicationRecord
  # Track status changes for notifications
  attribute :previous_status_value

  # Callbacks
  before_update :track_status_change
  after_update :notify_status_change
  after_create :create_default_board_columns
  after_create :track_creation_context
  after_update :track_update_context, if: :saved_changes?

  # Notification Callbacks
  after_commit :notify_title_change, on: :update, if: :saved_change_to_title?
  after_commit :notify_status_change, on: :update, if: :saved_change_to_status?

  # Associations
  belongs_to :owner, class_name: "User", foreign_key: "user_id"
  has_many :list_items, dependent: :destroy

  # NEW: Parent-Child List Relationships using the new database structure
  belongs_to :parent_list, class_name: "List", optional: true
  has_many :sub_lists, class_name: "List", foreign_key: "parent_list_id", dependent: :destroy

  has_many :board_columns, dependent: :destroy
  has_many :collaborators, as: :collaboratable, dependent: :destroy
  has_many :collaborator_users, through: :collaborators, source: :user
  has_many :invitations, as: :invitable, dependent: :destroy
  has_many :comments, as: :commentable, dependent: :destroy
  has_many :parent_relationships, as: :parent, class_name: "Relationship", dependent: :destroy
  has_many :child_relationships, as: :child, class_name: "Relationship", dependent: :destroy
  has_many :children, through: :parent_relationships, source: :child, source_type: [ "ListItem", "List" ]
  has_many :parents, through: :child_relationships, source: :parent, source_type: [ "ListItem", "List" ]

  # Validations
  validates :title, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: 1000 }
  validates :status, presence: true
  # Prevent circular references
  validate :cannot_be_parent_of_itself

  # Enums (Rails only, not in PostgreSQL)
  enum :status, {
    draft: 0,
    active: 1,
    completed: 2,
    archived: 3
  }, prefix: true

  # Define enum for list_type
  enum :list_type, {
    personal: 0,
    professional: 1
  }, prefix: true

  # Define enum for public_permission
  enum :public_permission, {
    public_read: 0,
    public_write: 1
  }, prefix: true

  # Scopes
  scope :active, -> { where(status: :active) }
  scope :owned_by, ->(user) { where(user: user) }
  scope :accessible_by, ->(user) {
    joins("LEFT JOIN collaborators ON lists.id = collaborators.collaboratable_id AND collaborators.collaboratable_type = 'List'")
      .where("lists.user_id = ? OR collaborators.user_id = ?", user.id, user.id)
      .group("lists.id")  # Use GROUP BY instead of DISTINCT
  }
  scope :recent, -> { order(updated_at: :desc) }

  # NEW: Hierarchy scopes using the new database structure
  scope :parent_lists, -> { where(parent_list_id: nil) }
  scope :sub_lists, -> { where.not(parent_list_id: nil) }

  # Callbacks
  before_create :generate_public_slug, if: :is_public?

  # Methods

  # Check if user can read this list
  def readable_by?(user)
    return false unless user
    return true if owner == user
    return true if is_public?

    collaborators.exists?(user: user)
  end

  def writable_by?(user)
    return false unless user
    return true if owner == user
    return true if is_public? && public_permission_public_write?

    collaborators.permission_write.exists?(user: user)
  end

  # Method for backward compatibility and semantic clarity
  def can_collaborate?(user)
    collaboratable_by?(user)
  end

  def collaboratable_by?(user)
    return false unless user
    return true if owner == user
    return true if is_public? && public_permission_public_write?

    collaborators.exists?(user: user)
  end

  # NEW: Hierarchy methods using the new database structure
  def is_parent_list?
    parent_list_id.nil? && sub_lists.any?
  end

  def is_sub_list?
    parent_list_id.present?
  end

  def root_list
    return self if parent_list_id.nil?
    parent_list.root_list
  end

  def all_sub_lists
    sub_lists.includes(:sub_lists)
  end

  # Get total items count including all sub-lists
  def total_items_count
    count = list_items_count
    sub_lists.each { |sub_list| count += sub_list.total_items_count }
    count
  end

  # Get completion percentage including sub-lists
  def total_completion_percentage
    total_items = total_items_count
    return 0 if total_items.zero?

    completed_items = list_items.completed.count
    sub_lists.each { |sub_list| completed_items += sub_list.list_items.completed.count }

    ((completed_items.to_f / total_items) * 100).round
  end

  # Generate slug for public lists
  def generate_public_slug
    return unless is_public?

    base_slug = title.parameterize
    slug_candidate = base_slug

    counter = 1
    while List.where(public_slug: slug_candidate).exists?
      slug_candidate = "#{base_slug}-#{counter}"
      counter += 1
    end

    self.public_slug = slug_candidate
  end

  # Status update methods
  def mark_completed!
    update!(status: :completed)
  end

  def mark_active!
    update!(status: :active)
  end

  def archive!
    update!(status: :archived)
  end

  private

  def cannot_be_parent_of_itself
    if parent_list_id == id
      errors.add(:parent_list_id, "cannot be the same as the list itself")
    end
  end

  def track_status_change
    @previous_status_value = status_was if status_changed?
  end

  def notify_status_change
    return unless @previous_status_value && @previous_status_value != status

    NotificationService.new.notify_list_status_change(self, @previous_status_value, status)
  end

  def notify_title_change
    NotificationService.new.notify_list_title_change(self)
  end

  def create_default_board_columns
    return if board_columns.any?

    default_columns = [
      { name: "To Do", position: 0 },
      { name: "In Progress", position: 1 },
      { name: "Done", position: 2 }
    ]

    default_columns.each do |column_attrs|
      board_columns.create!(column_attrs)
    end
  end

  def track_creation_context
    if Current.user
      ConversationContext.track_action(
        user: Current.user,
        action: "list_created",
        entity: self,
        metadata: {
          list_type: list_type,
          auto_tracked: true
        }
      )
    end
  end

  def track_update_context
    if Current.user
      changes_summary = saved_changes.keys.reject { |k| k == "updated_at" }
      return if changes_summary.empty?

      ConversationContext.track_action(
        user: Current.user,
        action: "list_updated",
        entity: self,
        metadata: {
          changed_fields: changes_summary,
          auto_tracked: true
        }
      )
    end
  end
end
