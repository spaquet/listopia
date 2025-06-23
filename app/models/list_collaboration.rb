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
