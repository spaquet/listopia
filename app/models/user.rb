# app/models/user.rb
class User < ApplicationRecord
  has_secure_password

  # Associations
  has_many :lists, dependent: :destroy
  has_many :list_collaborations, dependent: :destroy
  has_many :collaborated_lists, through: :list_collaborations, source: :list
  has_many :magic_links, dependent: :destroy

  # Validations
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true

  # Callbacks
  before_create :generate_email_verification_token

  # Scopes
  scope :verified, -> { where.not(email_verified_at: nil) }

  # Methods

  # Generate a secure token for email verification
  def generate_email_verification_token
    self.email_verification_token = SecureRandom.urlsafe_base64(32)
  end

  # Check if user's email is verified
  def email_verified?
    email_verified_at.present?
  end

  # Mark email as verified
  def verify_email!
    update!(email_verified_at: Time.current, email_verification_token: nil)
  end

  # Generate magic link token
  def generate_magic_link_token
    magic_links.create!(
      token: SecureRandom.urlsafe_base64(32),
      expires_at: 15.minutes.from_now
    )
  end

  # Get all accessible lists (owned + collaborated)
  def accessible_lists
    List.where(id: lists.pluck(:id) + collaborated_lists.pluck(:id))
  end
end

# app/models/list.rb
class List < ApplicationRecord
  # Associations
  belongs_to :owner, class_name: 'User', foreign_key: 'user_id'
  has_many :list_items, dependent: :destroy
  has_many :list_collaborations, dependent: :destroy
  has_many :collaborators, through: :list_collaborations, source: :user

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

  # Scopes
  scope :active, -> { where(status: :active) }
  scope :owned_by, ->(user) { where(user: user) }
  scope :accessible_by, ->(user) {
    joins("LEFT JOIN list_collaborations ON lists.id = list_collaborations.list_id")
      .where("lists.user_id = ? OR list_collaborations.user_id = ?", user.id, user.id)
      .distinct
  }

  # Methods

  # Check if user can read this list
  def readable_by?(user)
    return false unless user

    owner == user ||
    list_collaborations.exists?(user: user, permission: ['read', 'collaborate'])
  end

  # Check if user can collaborate on this list
  def collaboratable_by?(user)
    return false unless user

    owner == user ||
    list_collaborations.exists?(user: user, permission: 'collaborate')
  end

  # Add collaborator with specific permission
  def add_collaborator(user, permission: 'read')
    list_collaborations.find_or_create_by(user: user) do |collaboration|
      collaboration.permission = permission
    end
  end

  # Remove collaborator
  def remove_collaborator(user)
    list_collaborations.find_by(user: user)&.destroy
  end

  # Get completion percentage
  def completion_percentage
    return 0 if list_items.empty?

    completed_items = list_items.where(completed: true).count
    ((completed_items.to_f / list_items.count) * 100).round(2)
  end
end

# app/models/list_item.rb
class ListItem < ApplicationRecord
  # Associations
  belongs_to :list
  belongs_to :assigned_user, class_name: 'User', optional: true

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

# app/models/list_collaboration.rb
class ListCollaboration < ApplicationRecord
  # Associations
  belongs_to :list
  belongs_to :user

  # Validations
  validates :user_id, uniqueness: { scope: :list_id }
  validates :permission, presence: true

  # Enums
  enum :permission, {
    read: 0,
    collaborate: 1
  }, prefix: true

  # Scopes
  scope :readers, -> { where(permission: :read) }
  scope :collaborators, -> { where(permission: :collaborate) }

  # Methods

  # Check if collaboration allows editing
  def can_edit?
    permission_collaborate?
  end

  # Check if collaboration allows reading
  def can_read?
    permission_read? || permission_collaborate?
  end
end

# app/models/magic_link.rb
class MagicLink < ApplicationRecord
  # Associations
  belongs_to :user

  # Validations
  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true

  # Scopes
  scope :valid, -> { where('expires_at > ?', Time.current) }
  scope :expired, -> { where('expires_at <= ?', Time.current) }

  # Methods

  # Check if magic link is valid
  def valid?
    expires_at > Time.current && !used_at.present?
  end

  # Mark magic link as used
  def use!
    update!(used_at: Time.current)
  end

  # Find valid magic link by token
  def self.find_valid_by_token(token)
    valid.find_by(token: token, used_at: nil)
  end
end
