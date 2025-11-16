# app/models/organization_membership.rb
# == Schema Information
#
# Table name: organization_memberships
#
#  id              :uuid             not null, primary key
#  joined_at       :datetime         not null
#  metadata        :jsonb            not null
#  role            :integer          default("member"), not null
#  status          :integer          default("active"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#  user_id         :uuid             not null
#
# Indexes
#
#  index_organization_memberships_on_joined_at                    (joined_at)
#  index_organization_memberships_on_organization_id              (organization_id)
#  index_organization_memberships_on_organization_id_and_user_id  (organization_id,user_id) UNIQUE
#  index_organization_memberships_on_role                         (role)
#  index_organization_memberships_on_status                       (status)
#  index_organization_memberships_on_user_id                      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (user_id => users.id)
#
class OrganizationMembership < ApplicationRecord
  # Logidze for auditing changes
  has_logidze

  # Associations
  belongs_to :organization
  belongs_to :user
  has_many :team_memberships, dependent: :destroy

  # Validations
  validates :user_id, presence: true, uniqueness: { scope: :organization_id, message: "can only have one membership per organization" }
  validates :organization_id, presence: true
  validates :role, presence: true, inclusion: { in: %w(member admin owner), message: "%{value} is not a valid role" }
  validates :status, presence: true, inclusion: { in: %w(pending active suspended revoked), message: "%{value} is not a valid status" }
  validates :joined_at, presence: true

  # Enums
  enum :role, {
    member: 0,
    admin: 1,
    owner: 2
  }, prefix: true

  enum :status, {
    pending: 0,
    active: 1,
    suspended: 2,
    revoked: 3
  }, prefix: true

  # Callbacks
  before_validation :set_defaults, on: :create

  # Scopes
  scope :active, -> { where(status: :active) }
  scope :by_role, ->(role) { where(role: role) }
  scope :admins_and_owners, -> { where(role: ['admin', 'owner']) }

  # Methods
  def activate!
    update!(status: :active)
  end

  def suspend!
    update!(status: :suspended)
  end

  def revoke!
    update!(status: :revoked)
  end

  def can_manage_organization?
    role.in?(['admin', 'owner'])
  end

  def can_manage_teams?
    role.in?(['admin', 'owner'])
  end

  def can_manage_members?
    role.in?(['admin', 'owner'])
  end

  private

  def set_defaults
    self.joined_at ||= Time.current
    self.status ||= 'active'
    self.role ||= 'member'
  end
end
