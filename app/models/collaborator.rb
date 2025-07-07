# == Schema Information
#
# Table name: collaborators
#
#  id                  :uuid             not null, primary key
#  collaboratable_type :string           not null
#  permission          :integer          default(0), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  collaboratable_id   :uuid             not null
#  user_id             :uuid             not null
#
# Indexes
#
#  index_collaborators_on_collaboratable           (collaboratable_type,collaboratable_id)
#  index_collaborators_on_collaboratable_and_user  (collaboratable_id,collaboratable_type,user_id) UNIQUE
#  index_collaborators_on_user_id                  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#

# app/models/collaborator.rb
class Collaborator < ApplicationRecord
  belongs_to :collaboratable, polymorphic: true
  belongs_to :user

  # Add role support
  resourcify

  enum :permission, {
    read: 0,
    write: 1
  }, prefix: true

  validates :user_id, uniqueness: { scope: [ :collaboratable_type, :collaboratable_id ] }
  validates :permission, presence: true

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
end
