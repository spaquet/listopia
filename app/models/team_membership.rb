# app/models/team_membership.rb
# == Schema Information
#
# Table name: team_memberships
#
#  id                         :uuid             not null, primary key
#  joined_at                  :datetime         not null
#  metadata                   :jsonb            not null
#  role                       :string           default("member"), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  organization_membership_id :uuid             not null
#  team_id                    :uuid             not null
#  user_id                    :uuid             not null
#
# Indexes
#
#  index_team_memberships_on_joined_at                   (joined_at)
#  index_team_memberships_on_organization_membership_id  (organization_membership_id)
#  index_team_memberships_on_role                        (role)
#  index_team_memberships_on_team_id                     (team_id)
#  index_team_memberships_on_team_id_and_user_id         (team_id,user_id) UNIQUE
#  index_team_memberships_on_user_id                     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_membership_id => organization_memberships.id)
#  fk_rails_...  (team_id => teams.id)
#  fk_rails_...  (user_id => users.id)
#
class TeamMembership < ApplicationRecord
  # Logidze for auditing changes
  has_logidze

  # Associations
  belongs_to :team
  belongs_to :user
  belongs_to :organization_membership

  # Validations
  validates :user_id, presence: true, uniqueness: { scope: :team_id, message: "can only have one membership per team" }
  validates :team_id, presence: true
  validates :organization_membership_id, presence: true
  validates :role, presence: true, inclusion: { in: %w(member lead admin), message: "%{value} is not a valid role" }
  validates :joined_at, presence: true
  validate :user_must_be_org_member

  # Enums
  enum :role, {
    member: 0,
    lead: 1,
    admin: 2
  }, prefix: true

  # Callbacks
  before_validation :set_defaults, on: :create
  before_validation :set_organization_membership, on: :create

  # Scopes
  scope :by_role, ->(role) { where(role: role) }
  scope :admins_and_leads, -> { where(role: ['admin', 'lead']) }

  # Methods
  def can_manage_team?
    role.in?(['admin', 'lead'])
  end

  private

  def set_defaults
    self.joined_at ||= Time.current
    self.role ||= 'member'
  end

  def set_organization_membership
    return if organization_membership.present?

    self.organization_membership = team.organization.membership_for(user)
  end

  def user_must_be_org_member
    return if organization_membership.present?
    return if team&.organization&.member?(user)

    errors.add(:user, "must be a member of the organization first")
  end
end
