# == Schema Information
#
# Table name: ai_agent_interactions
#
#  id                   :uuid             not null, primary key
#  answer               :text
#  answered_at          :datetime
#  asked_at             :datetime
#  options              :jsonb            not null
#  question             :text             not null
#  status               :integer          default("pending"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  ai_agent_run_id      :uuid             not null
#  ai_agent_run_step_id :uuid
#
# Indexes
#
#  index_ai_agent_interactions_on_ai_agent_run_id             (ai_agent_run_id)
#  index_ai_agent_interactions_on_ai_agent_run_id_and_status  (ai_agent_run_id,status)
#  index_ai_agent_interactions_on_ai_agent_run_step_id        (ai_agent_run_step_id)
#  index_ai_agent_interactions_on_asked_at                    (asked_at)
#
# Foreign Keys
#
#  fk_rails_...  (ai_agent_run_id => ai_agent_runs.id)
#  fk_rails_...  (ai_agent_run_step_id => ai_agent_run_steps.id)
#

class AiAgentInteraction < ApplicationRecord
  belongs_to :ai_agent_run
  belongs_to :ai_agent_run_step, optional: true

  enum :status, {
    pending: 0,
    answered: 1,
    skipped: 2
  }, prefix: true

  validates :question, presence: true
  validates :ai_agent_run_id, presence: true

  scope :pending, -> { where(status: :pending) }
  scope :answered, -> { where(status: :answered) }
  scope :recent, -> { order(created_at: :desc) }

  before_save :set_asked_at, if: :will_save_change_to_question?

  # Mark as answered by the user
  def mark_answered!(answer_text)
    update!(
      answer: answer_text,
      status: :answered,
      answered_at: Time.current
    )
  end

  # Mark as skipped (user declined to answer)
  def mark_skipped!
    update!(
      status: :skipped,
      answered_at: Time.current
    )
  end

  private

  def set_asked_at
    self.asked_at = Time.current if asked_at.blank?
  end
end
