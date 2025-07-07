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
#  user_id                   :uuid             not null
#
# Indexes
#
#  index_lists_on_created_at                 (created_at)
#  index_lists_on_is_public                  (is_public)
#  index_lists_on_list_collaborations_count  (list_collaborations_count)
#  index_lists_on_list_items_count           (list_items_count)
#  index_lists_on_list_type                  (list_type)
#  index_lists_on_public_permission          (public_permission)
#  index_lists_on_public_slug                (public_slug) UNIQUE
#  index_lists_on_status                     (status)
#  index_lists_on_user_id                    (user_id)
#  index_lists_on_user_id_and_created_at     (user_id,created_at)
#  index_lists_on_user_id_and_status         (user_id,status)
#  index_lists_on_user_is_public             (user_id,is_public)
#  index_lists_on_user_list_type             (user_id,list_type)
#  index_lists_on_user_status                (user_id,status)
#  index_lists_on_user_status_list_type      (user_id,status,list_type)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#

# app/models/list.rb
class List < ApplicationRecord
  # Track status changes for notifications
  attribute :previous_status_value

  # Callbacks
  before_update :track_status_change
  after_update :notify_status_change
  after_create :create_default_board_columns

  # Notification Callbacks
  after_commit :notify_title_change, on: :update, if: :saved_change_to_title?
  after_commit :notify_status_change, on: :update, if: :saved_change_to_status?

  # Associations
  belongs_to :owner, class_name: "User", foreign_key: "user_id"
  has_many :list_items, dependent: :destroy

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
  # This is used to control public access permissions
  # 0 - public_read: Public can read the list
  # 1 - public_write: Public can write to the list (e.g., add items)
  # Note: This is not a PostgreSQL enum, but a Rails enum for application logic
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
    return true if is_public? && public_permission_write?

    collaborators.permission_write.exists?(user: user)
  end

  # Check if user can collaborate on this list
  def collaboratable_by?(user)
    return false unless user

    owner == user ||
    collaborators.exists?(user: user, permission: "collaborate")  # Change from list_collaborations
  end

  # Add collaborator with specific permission
  def add_collaborator(user, permission: :read)
    collaborators.find_or_create_by(user: user) do |collaboration|
      collaboration.permission = permission
    end
  end

  # Remove collaborator
  def remove_collaborator(user)
    collaborators.find_by(user: user)&.destroy
  end

  def has_collaborator?(user)
    collaborators.exists?(user: user)
  end

  def collaborator_permission(user)
    collaborators.find_by(user: user)&.permission
  end

  # Get completion percentage
  def completion_percentage
    return 0 if list_items.empty?

    completed_items = list_items.where(completed: true).count
    ((completed_items.to_f / list_items.count) * 100).round(2)
  end

  private

  def generate_public_slug
    self.public_slug = SecureRandom.urlsafe_base64(8) if public_slug.blank?
  end

  def track_status_change
    if status_changed?
      self.previous_status_value = status_was
    end
  end

  def notify_status_change
    if saved_change_to_status? && Current.user
      NotificationService.new(Current.user)
                         .notify_list_status_changed(self, previous_status_value, status)
    end
  end

  # Notify collaborators of title change
  def notify_title_change
    return unless Current.user
    recipients = collaborators.where.not(id: Current.user.id)
    return if recipients.empty?

    ListTitleChangedNotifier.deliver_to_enabled_users(recipients, actor_id: Current.user.id, list_id: id)
  end

  # Notify collaborators of status change
  def notify_status_change
    return unless Current.user
    recipients = collaborators.where.not(id: Current.user.id)
    return if recipients.empty?

    ListStatusChangedNotifier.deliver_to_enabled_users(
      recipients,
      actor_id: Current.user.id,
      list_id: id,
      new_status: status
    )
  end

  # Create default board columns after list creation
  def create_default_board_columns
    board_columns.create([
      { name: "To Do", position: 0 },
      { name: "In Progress", position: 1 },
      { name: "Done", position: 2 }
    ])
  end
end
