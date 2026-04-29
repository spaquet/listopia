# == Schema Information
#
# Table name: ai_agents
#
#  id                        :uuid             not null, primary key
#  average_rating            :float
#  body_context_config       :jsonb            not null
#  description               :text
#  discarded_at              :datetime
#  embedding                 :vector(1536)
#  embedding_generated_at    :datetime
#  instructions              :text
#  max_steps                 :integer          default(20)
#  max_tokens_per_day        :integer          default(50000)
#  max_tokens_per_month      :integer          default(500000)
#  max_tokens_per_run        :integer          default(4000)
#  metadata                  :jsonb            not null
#  model                     :string           default("gpt-4o-mini")
#  name                      :string           not null
#  parameters                :jsonb            not null
#  pre_run_questions         :jsonb            not null
#  prompt                    :text             not null
#  rate_limit_per_hour       :integer          default(10)
#  requires_embedding_update :boolean          default(FALSE), not null
#  run_count                 :integer          default(0)
#  scope                     :integer          default("system_agent"), not null
#  slug                      :string           not null
#  status                    :integer          default("draft"), not null
#  success_count             :integer          default(0)
#  timeout_seconds           :integer          default(120)
#  tokens_month_year         :integer
#  tokens_today_date         :date
#  tokens_used_this_month    :integer          default(0)
#  tokens_used_today         :integer          default(0)
#  trigger_config            :jsonb            not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  organization_id           :uuid
#  user_id                   :uuid
#
# Indexes
#
#  index_ai_agents_on_discarded_at              (discarded_at)
#  index_ai_agents_on_embedding                 (embedding) USING ivfflat
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
  has_neighbors :embedding

  # Associations
  belongs_to :user,         optional: true
  belongs_to :organization, optional: true
  has_many   :ai_agent_team_memberships, dependent: :destroy
  has_many   :teams, through: :ai_agent_team_memberships
  has_many   :ai_agent_resources, dependent: :destroy
  has_many   :ai_agent_runs, dependent: :destroy
  has_many   :ai_agent_interactions, through: :ai_agent_runs

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
  validates :instructions, length: { maximum: 10000 }, allow_blank: true
  validates :scope, presence: true
  validates :slug, presence: true
  validates :trigger_config, presence: true
  validate  :scope_consistency
  validate  :validate_trigger_config
  validate  :validate_pre_run_questions

  # Callbacks
  before_validation :generate_slug
  before_save :normalize_parameters, :mark_embedding_update_if_needed
  after_save :schedule_embedding_update, if: :requires_embedding_update?

  # Scopes
  scope :system_level,      -> { where(scope: :system_agent) }
  scope :org_agent,         -> { where(scope: :org_agent) }
  scope :team_agent,        -> { where(scope: :team_agent) }
  scope :user_agent,        -> { where(scope: :user_agent) }
  scope :for_organization,  ->(org) { where(organization_id: org.id) }
  scope :for_team,          ->(team) { joins(:ai_agent_team_memberships).where(ai_agent_team_memberships: { team_id: team.id }).distinct }
  scope :for_user,          ->(user) { where(user_id: user.id) }
  scope :available,         -> { where(status: :active).kept }
  scope :with_trigger_type, ->(type) { where("trigger_config->>'type' = ?", type) }
  scope :with_event_trigger, ->(event_type) { where("trigger_config->>'type' = 'event' AND trigger_config->>'event_type' = ?", event_type) }

  # Embedding search
  scope :similar_to, ->(agent, limit: 5) {
    where.not(id: agent.id)
      .where("embedding IS NOT NULL")
      .nearest_neighbors(:embedding, agent.embedding, distance: "cosine")
      .limit(limit)
  }

  scope :find_for_task, ->(task_text, limit: 5) {
    # This is designed to be called with a task description string
    # In practice, you'd generate an embedding for task_text via EmbeddingGenerationService
    # and then use nearest_neighbors. For now, this is a placeholder.
    where("embedding IS NOT NULL").limit(limit)
  }

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

  # Embedding support
  def content_for_embedding
    [ name, description, instructions ].compact.join("\n\n")
  end

  def embedding_content_changed?
    saved_change_to_name? || saved_change_to_description? || saved_change_to_instructions?
  end

  private

  def reset_daily_counter!
    update_columns(tokens_used_today: 0, tokens_today_date: Date.current)
  end

  def generate_slug
    return if slug.present?
    self.slug = name.parameterize
  end

  def normalize_parameters
    if parameters.is_a?(String) && parameters.present?
      begin
        self.parameters = JSON.parse(parameters)
      rescue JSON::ParserError
        self.parameters = {}
      end
    elsif parameters.nil?
      self.parameters = {}
    end
  end

  def mark_embedding_update_if_needed
    self.requires_embedding_update = true if embedding_content_changed?
  end

  def scope_consistency
    case scope
    when "org_agent", "team_agent"
      errors.add(:organization_id, "must be set for org/team agents") unless organization_id.present?
    when "user_agent"
      errors.add(:user_id, "must be set for user agents") unless user_id.present?
    end
  end

  def validate_trigger_config
    return if trigger_config.blank?

    unless trigger_config.is_a?(Hash)
      errors.add(:trigger_config, "must be a valid JSON object")
      return
    end

    trigger_type = trigger_config["type"]
    valid_types = %w[manual event schedule]

    unless valid_types.include?(trigger_type)
      errors.add(:trigger_config, "type must be one of: #{valid_types.join(', ')}")
      return
    end

    if trigger_type == "event" && trigger_config["event_type"].blank?
      errors.add(:trigger_config, "event_type must be specified for event triggers")
    end

    if trigger_type == "schedule" && trigger_config["cron"].blank?
      errors.add(:trigger_config, "cron must be specified for scheduled triggers")
    end
  end

  def validate_pre_run_questions
    return if pre_run_questions.blank?

    unless pre_run_questions.is_a?(Array)
      errors.add(:pre_run_questions, "must be a valid JSON array")
      return
    end

    pre_run_questions.each_with_index do |q, idx|
      unless q.is_a?(Hash)
        errors.add(:pre_run_questions, "question #{idx} must be an object")
        next
      end

      unless q["question"].present?
        errors.add(:pre_run_questions, "question #{idx} must have a 'question' field")
      end

      unless q["key"].present?
        errors.add(:pre_run_questions, "question #{idx} must have a 'key' field")
      end
    end
  end

  def schedule_embedding_update
    AgentEmbeddingJob.perform_later(id) if requires_embedding_update?
  end
end
