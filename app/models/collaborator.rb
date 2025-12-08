# == Schema Information
#
# Table name: collaborators
#
#  id                  :uuid             not null, primary key
#  collaboratable_type :string           not null
#  granted_roles       :string           default([]), not null, is an Array
#  metadata            :jsonb            not null
#  permission          :integer          default("read"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  collaboratable_id   :uuid             not null
#  organization_id     :uuid
#  user_id             :uuid             not null
#
# Indexes
#
#  index_collaborators_on_collaboratable           (collaboratable_type,collaboratable_id)
#  index_collaborators_on_collaboratable_and_user  (collaboratable_id,collaboratable_type,user_id) UNIQUE
#  index_collaborators_on_organization_id          (organization_id)
#  index_collaborators_on_user_id                  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#

# app/models/collaborator.rb
class Collaborator < ApplicationRecord
  # Logidza for auditing changes
  has_logidze

  belongs_to :collaboratable, polymorphic: true
  belongs_to :user
  belongs_to :organization, optional: true

  # Add role support
  resourcify

  enum :permission, {
    read: 0,
    write: 1
  }, prefix: true

  validates :user_id, uniqueness: { scope: [ :collaboratable_type, :collaboratable_id ] }
  validates :permission, presence: true
  validate :user_must_be_in_same_organization

  # Callbacks
  after_commit :notify_permission_changed, on: :update, if: :saved_change_to_permission?

  # Scopes
  scope :readers, -> { where(permission: :read) }
  scope :writers, -> { where(permission: :write) }

  # Helper methods
  def can_edit?
    permission_write?
  end

  def can_view?
    true # All collaborators can view
  end

  def display_name
    user.name || user.email
  end

  private

  def user_must_be_in_same_organization
    return unless organization_id.present?
    return if user&.in_organization?(organization)

    errors.add(:user, "must be in the same organization as the resource")
  end

  def notify_permission_changed
    return unless Current.user

    old_permission = permission_before_last_save
    NotificationService.new(Current.user)
                      .notify_permission_changed(self, old_permission)
  end
end
