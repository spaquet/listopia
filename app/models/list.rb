# app/models/list.rb
# == Schema Information
#
# Table name: lists
#
#  id                        :uuid             not null, primary key
#  color_theme               :string           default("blue")
#  description               :text
#  is_public                 :boolean          default(FALSE), not null
#  list_collaborations_count :integer          default(0), not null
#  list_items_count          :integer          default(0), not null
#  list_type                 :integer          default("personal"), not null
#  metadata                  :json
#  public_permission         :integer          default("public_read"), not null
#  public_slug               :string
#  status                    :integer          default("draft"), not null
#  title                     :string           not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  organization_id           :uuid
#  parent_list_id            :uuid
#  team_id                   :uuid
#  user_id                   :uuid             not null
#
# Indexes
#
#  index_lists_on_created_at                     (created_at)
#  index_lists_on_is_public                      (is_public)
#  index_lists_on_list_collaborations_count      (list_collaborations_count)
#  index_lists_on_list_items_count               (list_items_count)
#  index_lists_on_list_type                      (list_type)
#  index_lists_on_organization_id                (organization_id)
#  index_lists_on_parent_list_id                 (parent_list_id)
#  index_lists_on_parent_list_id_and_created_at  (parent_list_id,created_at)
#  index_lists_on_public_permission              (public_permission)
#  index_lists_on_public_slug                    (public_slug) UNIQUE
#  index_lists_on_status                         (status)
#  index_lists_on_team_id                        (team_id)
#  index_lists_on_user_id                        (user_id)
#  index_lists_on_user_id_and_created_at         (user_id,created_at)
#  index_lists_on_user_id_and_status             (user_id,status)
#  index_lists_on_user_is_public                 (user_id,is_public)
#  index_lists_on_user_list_type                 (user_id,list_type)
#  index_lists_on_user_parent                    (user_id,parent_list_id)
#  index_lists_on_user_status                    (user_id,status)
#  index_lists_on_user_status_list_type          (user_id,status,list_type)
#
# Foreign Keys
#
#  fk_rails_...  (parent_list_id => lists.id)
#  fk_rails_...  (user_id => users.id)
#
class List < ApplicationRecord
  # Track status changes for notifications
  attribute :previous_status_value

  # Logidzy for auditing changes
  has_logidze

  # Callbacks
  before_update :track_status_change
  after_update :notify_status_change
  after_create :create_default_board_columns

  # Notification Callbacks
  after_commit :notify_title_change, on: :update, if: :saved_change_to_title?
  after_commit :notify_status_change, on: :update, if: :saved_change_to_status?
  after_commit :notify_list_archived, on: :update, if: :status_archived?

  # Associations
  belongs_to :owner, class_name: "User", foreign_key: "user_id"
  belongs_to :organization, optional: true
  belongs_to :team, optional: true
  has_many :list_items, dependent: :destroy

  # Comments
  has_many :comments, as: :commentable, dependent: :destroy

  # Parent-Child List Relationships using the new database structure
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
  # Prevent circular references - only check on updates, not creates
  validate :cannot_be_parent_of_itself, on: :update

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
  scope :by_organization, ->(org) { where(organization: org) }
  scope :for_team, ->(team) { where(team: team) }

  # NEW: Hierarchy scopes using the new database structure
  scope :parent_lists, -> { where(parent_list_id: nil) }
  scope :sub_lists, -> { where.not(parent_list_id: nil) }

  # Callbacks
  before_create :generate_public_slug, if: :is_public?
  after_save :sync_organization_id_from_team, if: :team_id_changed?

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

    completed_items = list_items.status_completed.count
    sub_lists.each { |sub_list| completed_items += sub_list.list_items.status_completed.count }

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

  def sync_organization_id_from_team
    return unless team_id.present?

    update_column(:organization_id, team.organization_id) if organization_id != team.organization_id
  end

  private

  def cannot_be_parent_of_itself
    if parent_list_id.present? && parent_list_id == id
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

  def notify_list_archived
    return unless Current.user && status_archived?

    NotificationService.new(Current.user).notify_list_archived(self)
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
end
