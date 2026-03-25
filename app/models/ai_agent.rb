# == Schema Information
#
# Table name: ai_agents
#
#  id                     :uuid             not null, primary key
#  average_rating         :float
#  description            :text
#  discarded_at           :datetime
#  max_steps              :integer          default(20)
#  max_tokens_per_day     :integer          default(50000)
#  max_tokens_per_month   :integer          default(500000)
#  max_tokens_per_run     :integer          default(4000)
#  metadata               :jsonb            not null
#  model                  :string           default("gpt-4o-mini")
#  name                   :string           not null
#  parameters             :jsonb            not null
#  prompt                 :text             not null
#  rate_limit_per_hour    :integer          default(10)
#  run_count              :integer          default(0)
#  scope                  :integer          default("system_agent"), not null
#  slug                   :string           not null
#  status                 :integer          default("draft"), not null
#  success_count          :integer          default(0)
#  timeout_seconds        :integer          default(120)
#  tokens_month_year      :integer
#  tokens_today_date      :date
#  tokens_used_this_month :integer          default(0)
#  tokens_used_today      :integer          default(0)
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  organization_id        :uuid
#  user_id                :uuid
#
# Indexes
#
#  index_ai_agents_on_discarded_at              (discarded_at)
#  index_ai_agents_on_organization_id           (organization_id)
#  index_ai_agents_on_organization_id_and_slug  (organization_id,slug) UNIQUE
#  index_ai_agents_on_run_count                 (run_count)
#  index_ai_agents_on_scope                     (scope)
#  index_ai_agents_on_status                    (status)
#  index_ai_agents_on_user_id                   (user_id)
#  index_ai_agents_on_user_id_and_slug          (user_id,slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (user_id => users.id)
#

class AiAgent < ApplicationRecord
  include Discard::Model
  has_logidze
  acts_as_taggable_on :tags

  # Associations
  belongs_to :user,         optional: true
  belongs_to :organization, optional: true
  has_many   :ai_agent_team_memberships, dependent: :destroy
  has_many   :teams, through: :ai_agent_team_memberships
  has_many   :ai_agent_resources, dependent: :destroy
  has_many   :ai_agent_runs, dependent: :destroy

  # Enums
  enum :scope, {
    system_agent: 0,
    org_agent:    1,
    team_agent:   2,
    user_agent:   3
  }, prefix: true

  enum :status, {
    draft:    0,
    active:   1,
    paused:   2,
    archived: 3
  }, prefix: true

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :prompt, presence: true, length: { minimum: 10 }
  validates :scope, presence: true
  validates :slug, presence: true
  validate  :scope_consistency

  # Callbacks
  before_validation :generate_slug

  # Scopes
  scope :system_level,      -> { where(scope: :system_agent) }
  scope :org_agent,         -> { where(scope: :org_agent) }
  scope :team_agent,        -> { where(scope: :team_agent) }
  scope :user_agent,        -> { where(scope: :user_agent) }
  scope :for_organization,  ->(org) { where(organization_id: org.id) }
  scope :for_team,          ->(team) { joins(:ai_agent_team_memberships).where(ai_agent_team_memberships: { team_id: team.id }).distinct }
  scope :for_user,          ->(user) { where(user_id: user.id) }
  scope :available,         -> { where(status: :active).kept }

  # Access check: can this user invoke this agent?
  def accessible_by?(user)
    case scope
    when "system_agent"
      status_active?
    when "org_agent"
      status_active? && user.in_organization?(organization)
    when "team_agent"
      status_active? && teams.any? { |t| t.member?(user) }
    when "user_agent"
      status_active? && self.user == user
    else
      false
    end
  end

  # Can this user edit/manage this agent?
  def manageable_by?(user)
    case scope
    when "system_agent"
      false  # no one edits system agents from UI
    when "org_agent"
      return false unless organization
      membership = organization.membership_for(user)
      membership&.role.in?(%w[admin owner])
    when "team_agent"
      return false if teams.empty?
      teams.any? { |t| t.user_is_admin?(user) } ||
        (organization && organization.membership_for(user)&.role.in?(%w[admin owner]))
    when "user_agent"
      self.user == user
    else
      false
    end
  end

  def within_token_budget?(tokens_needed)
    (tokens_used_today + tokens_needed) <= max_tokens_per_day &&
      (tokens_used_this_month + tokens_needed) <= max_tokens_per_month
  end

  def increment_token_usage!(tokens)
    today = Date.current
    reset_daily_counter! unless tokens_today_date == today
    increment!(:tokens_used_today, tokens)
    increment!(:tokens_used_this_month, tokens)
  end

  private

  def reset_daily_counter!
    update_columns(tokens_used_today: 0, tokens_today_date: Date.current)
  end

  def generate_slug
    return if slug.present?
    self.slug = name.parameterize
  end

  def scope_consistency
    case scope
    when "org_agent", "team_agent"
      errors.add(:organization_id, "must be set for org/team agents") unless organization_id.present?
    when "user_agent"
      errors.add(:user_id, "must be set for user agents") unless user_id.present?
    end
  end
end
