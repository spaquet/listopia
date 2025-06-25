# app/models/list.rb
# == Schema Information
#
# Table name: lists
#
#  id          :uuid             not null, primary key
#  color_theme :string           default("blue")
#  description :text
#  is_public   :boolean          default(FALSE)
#  metadata    :json
#  public_slug :string
#  status      :integer          default("draft"), not null
#  title       :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  user_id     :uuid             not null
#
# Indexes
#
#  index_lists_on_created_at              (created_at)
#  index_lists_on_is_public               (is_public)
#  index_lists_on_public_slug             (public_slug) UNIQUE
#  index_lists_on_status                  (status)
#  index_lists_on_user_id                 (user_id)
#  index_lists_on_user_id_and_created_at  (user_id,created_at)
#  index_lists_on_user_id_and_status      (user_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
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
  scope :owned_by, ->(user) { where(user_id: user.id) }
  scope :accessible_by, ->(user) {
    left_joins(:list_collaborations)
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
    collaboration = list_collaborations.find_by(user: user)

    if collaboration
      collaboration.update!(permission: permission)
      collaboration
    else
      list_collaborations.create!(user: user, permission: permission)
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
