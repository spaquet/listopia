# app/models/team.rb
# == Schema Information
#
# Table name: teams
#
#  id              :uuid             not null, primary key
#  metadata        :jsonb            not null
#  name            :string           not null
#  slug            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  created_by_id   :uuid             not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_teams_on_created_at                (created_at)
#  index_teams_on_created_by_id             (created_by_id)
#  index_teams_on_organization_id           (organization_id)
#  index_teams_on_organization_id_and_slug  (organization_id,slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (organization_id => organizations.id)
#
class Team < ApplicationRecord
  # Logidze for auditing changes
  has_logidze

  # Associations
  belongs_to :organization
  belongs_to :creator, class_name: "User", foreign_key: "created_by_id"
  has_many :team_memberships, dependent: :destroy
  has_many :users, through: :team_memberships
  has_many :lists, dependent: :nullify

  # Validations
  validates :name, presence: true, length: { minimum: 1, maximum: 255 }
  validates :slug, presence: true, uniqueness: { scope: :organization_id, message: "must be unique within the organization" },
                    length: { minimum: 1, maximum: 255 },
                    format: { with: /\A[a-z0-9]([a-z0-9\-]*[a-z0-9])?\z/, message: "must be lowercase alphanumeric with hyphens" }
  validates :organization_id, presence: true
  validates :created_by_id, presence: true

  # Callbacks
  before_validation :generate_slug, if: :name_changed?
  after_create :add_creator_as_admin_member

  # Scopes
  scope :by_organization, ->(org) { where(organization: org) }

  # Methods
  def generate_slug
    return if slug.present?

    base_slug = name.parameterize
    slug_candidate = base_slug
    counter = 1

    while Team.where(organization: organization)
              .where(slug: slug_candidate)
              .where.not(id: id)
              .exists?
      slug_candidate = "#{base_slug}-#{counter}"
      counter += 1
    end

    self.slug = slug_candidate
  end

  # Check if user is a member of this team
  def member?(user)
    users.exists?(user.id)
  end

  # Get user's role in this team
  def user_role(user)
    team_memberships.find_by(user: user)&.role
  end

  # Get user's membership in this team
  def membership_for(user)
    team_memberships.find_by(user: user)
  end

  # Check if user has a specific role
  def user_has_role?(user, role)
    user_role(user) == role
  end

  # Check if user is an admin or lead
  def user_is_admin?(user)
    role = user_role(user)
    role.in?(['admin', 'lead'])
  end

  private

  # Add creator as admin member when team is created
  def add_creator_as_admin_member
    team_memberships.create!(
      user: creator,
      organization_membership_id: organization.membership_for(creator).id,
      role: 'admin'
    )
  end
end
