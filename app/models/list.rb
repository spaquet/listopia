# app/models/list.rb
class List < ApplicationRecord
  # Associations
  belongs_to :owner, class_name: "User", foreign_key: "user_id"
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

  # Callbacks
  before_create :generate_public_slug, if: :is_public?

  # Methods

  # Check if user can read this list
  def readable_by?(user)
    return false unless user

    owner == user ||
    list_collaborations.exists?(user: user, permission: [ "read", "collaborate" ]) ||
    is_public?
  end

  # Check if user can collaborate on this list
  def collaboratable_by?(user)
    return false unless user

    owner == user ||
    list_collaborations.exists?(user: user, permission: "collaborate")
  end

  # Add collaborator with specific permission
  def add_collaborator(user, permission: "read")
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

  private

  def generate_public_slug
    self.public_slug = SecureRandom.urlsafe_base64(8) if public_slug.blank?
  end
end
