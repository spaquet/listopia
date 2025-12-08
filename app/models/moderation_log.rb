# app/models/moderation_log.rb
#
# Audit trail for security and moderation actions.
# Tracks:
# - Prompt injection detection results
# - Content moderation flags
# - Violations and actions taken
#
# Scoped to organization for multi-tenant isolation.

# == Schema Information
#
# Table name: moderation_logs
#
#  id                    :uuid             not null, primary key
#  action_taken          :integer          default("logged")
#  details               :text
#  detected_patterns     :jsonb
#  moderation_scores     :jsonb
#  prompt_injection_risk :string           default("low")
#  violation_type        :integer          default("prompt_injection")
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  chat_id               :uuid
#  message_id            :uuid
#  organization_id       :uuid
#  user_id               :uuid
#
# Indexes
#
#  index_moderation_logs_on_action_taken                    (action_taken)
#  index_moderation_logs_on_chat_id                         (chat_id)
#  index_moderation_logs_on_message_id                      (message_id)
#  index_moderation_logs_on_organization_id                 (organization_id)
#  index_moderation_logs_on_organization_id_and_created_at  (organization_id,created_at)
#  index_moderation_logs_on_user_id                         (user_id)
#  index_moderation_logs_on_user_id_and_created_at          (user_id,created_at)
#  index_moderation_logs_on_violation_type                  (violation_type)
#
# Foreign Keys
#
#  fk_rails_...  (chat_id => chats.id)
#  fk_rails_...  (message_id => messages.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (user_id => users.id)
#
class ModerationLog < ApplicationRecord
  belongs_to :chat
  belongs_to :message, optional: true
  belongs_to :user
  belongs_to :organization

  enum :violation_type, {
    prompt_injection: 0,
    harmful_content: 1,
    hate_speech: 2,
    harassment: 3,
    self_harm: 4,
    sexual_content: 5,
    violence: 6,
    other: 7
  }

  enum :action_taken, {
    logged: 0,        # Just logged, message allowed
    warned: 1,        # User warned, message allowed
    blocked: 2,       # Message blocked, not sent to LLM
    archived: 3      # Chat archived due to repeated violations
  }

  # Validations
  validates :chat_id, presence: true
  validates :user_id, presence: true
  validates :organization_id, presence: true
  validates :violation_type, presence: true
  validates :action_taken, presence: true

  # Scopes
  scope :by_organization, ->(org) { where(organization_id: org.id) }
  scope :by_user, ->(user) { where(user_id: user.id) }
  scope :by_violation, ->(type) { where(violation_type: type) }
  scope :recent, -> { order(created_at: :desc) }
  scope :last_24_hours, -> { where("created_at > ?", 24.hours.ago) }
  scope :last_7_days, -> { where("created_at > ?", 7.days.ago) }

  # Analytics
  def self.violation_summary(organization, time_window = 24.hours)
    by_organization(organization)
      .where("created_at > ?", time_window.ago)
      .group(:violation_type)
      .count
  end

  def self.repeat_offenders(organization, time_window = 7.days, threshold = 3)
    by_organization(organization)
      .where("created_at > ?", time_window.ago)
      .group(:user_id)
      .having("count(*) >= ?", threshold)
      .pluck(:user_id)
  end

  # User has been flagged for this violation type
  def self.user_has_violation?(user, organization, violation_type)
    by_organization(organization)
      .by_user(user)
      .by_violation(violation_type)
      .exists?
  end

  # Count violations for a user in timeframe
  def self.user_violation_count(user, organization, time_window = 7.days)
    by_organization(organization)
      .by_user(user)
      .where("created_at > ?", time_window.ago)
      .count
  end

  # Auto-archive chat if threshold is exceeded
  def self.check_auto_archive(chat, organization)
    threshold = ENV.fetch("MODERATION_AUTO_ARCHIVE_THRESHOLD", "5").to_i
    return if threshold.zero?

    violation_count = where(chat_id: chat.id, action_taken: "blocked")
      .where("created_at > ?", 7.days.ago)
      .count

    if violation_count >= threshold
      chat.update(status: :archived)
      ModerationLog.create!(
        chat: chat,
        user: chat.user,
        organization: chat.organization,
        violation_type: :other,
        action_taken: :archived,
        details: "Chat auto-archived after #{violation_count} violations in past 7 days"
      )
    end
  end
end
