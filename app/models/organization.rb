# app/models/organization.rb
# == Schema Information
#
# Table name: organizations
#
#  id            :uuid             not null, primary key
#  metadata      :jsonb            not null
#  name          :string           not null
#  size          :integer          default("small"), not null
#  slug          :string           not null
#  status        :integer          default("active"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  created_by_id :uuid             not null
#
# Indexes
#
#  index_organizations_on_created_at     (created_at)
#  index_organizations_on_created_by_id  (created_by_id)
#  index_organizations_on_size           (size)
#  index_organizations_on_slug           (slug) UNIQUE
#  index_organizations_on_status         (status)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#
class Organization < ApplicationRecord
  # Logidze for auditing changes
  has_logidze

  # Associations
  belongs_to :creator, class_name: "User", foreign_key: "created_by_id"
  has_many :organization_memberships, dependent: :destroy
  has_many :users, through: :organization_memberships
  has_many :team_memberships, through: :teams
  has_many :teams, dependent: :destroy
  has_many :lists, dependent: :destroy
  has_many :invitations, dependent: :destroy

  # Validations
  validates :name, presence: true, length: { minimum: 1, maximum: 255 }
  validates :slug, presence: true, uniqueness: true, length: { minimum: 1, maximum: 255 },
                    format: { with: /\A[a-z0-9]([a-z0-9\-]*[a-z0-9])?\z/, message: "must be lowercase alphanumeric with hyphens" }
  validates :created_by_id, presence: true
  validates :status, presence: true

  # Enums
  enum :size, {
    small: 0,
    medium: 1,
    large: 2,
    enterprise: 3
  }, prefix: true

  enum :status, {
    active: 0,
    suspended: 1,
    deleted: 2
  }, prefix: true

  # Callbacks
  before_validation :generate_slug, if: :name_changed?

  # Scopes
  scope :active, -> { where(status: :active) }

  # Methods
  def generate_slug
    return if slug.present?

    base_slug = name.parameterize
    slug_candidate = base_slug
    counter = 1

    while Organization.where(slug: slug_candidate).where.not(id: id).exists?
      slug_candidate = "#{base_slug}-#{counter}"
      counter += 1
    end

    self.slug = slug_candidate
  end

  # Check if user is a member of this organization
  def member?(user)
    users.exists?(user)
  end

  # Get user's role in this organization
  def user_role(user)
    organization_memberships.find_by(user: user)&.role
  end

  # Get user's membership in this organization
  def membership_for(user)
    organization_memberships.find_by(user: user)
  end

  # Check if user has a specific role
  def user_has_role?(user, role)
    user_role(user) == role
  end

  # Check if user is an admin or owner
  def user_is_admin?(user)
    role = user_role(user)
    role.in?(['admin', 'owner'])
  end

  # Check if user is the owner
  def user_is_owner?(user)
    user_role(user) == 'owner'
  end

  # Suspend organization
  def suspend!
    update(status: :suspended)
  end

  # Reactivate organization
  def reactivate!
    update(status: :active)
  end
end
