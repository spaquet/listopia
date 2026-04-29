# == Schema Information
#
# Table name: ai_agent_runs
#
#  id                  :uuid             not null, primary key
#  awaiting_at         :datetime
#  cancellation_reason :text
#  completed_at        :datetime
#  error_message       :text
#  input_parameters    :jsonb            not null
#  input_tokens        :integer          default(0)
#  invocable_type      :string
#  last_activity_at    :datetime
#  metadata            :jsonb            not null
#  output_tokens       :integer          default(0)
#  paused_at           :datetime
#  pre_run_answers     :jsonb            not null
#  processing_time_ms  :integer
#  result_data         :jsonb            not null
#  result_summary      :text
#  started_at          :datetime
#  status              :integer          default("pending"), not null
#  steps_completed     :integer          default(0)
#  steps_total         :integer          default(0)
#  thinking_tokens     :integer          default(0)
#  total_tokens        :integer          default(0)
#  trigger_source      :string           default("manual"), not null
#  user_input          :text
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  ai_agent_id         :uuid             not null
#  invocable_id        :uuid
#  organization_id     :uuid             not null
#  parent_run_id       :uuid
#  user_id             :uuid             not null
#
# Indexes
#
#  index_ai_agent_runs_on_ai_agent_id                      (ai_agent_id)
#  index_ai_agent_runs_on_completed_at                     (completed_at)
#  index_ai_agent_runs_on_invocable_type_and_invocable_id  (invocable_type,invocable_id)
#  index_ai_agent_runs_on_last_activity_at                 (last_activity_at)
#  index_ai_agent_runs_on_organization_id                  (organization_id)
#  index_ai_agent_runs_on_parent_run_id                    (parent_run_id)
#  index_ai_agent_runs_on_started_at                       (started_at)
#  index_ai_agent_runs_on_status                           (status)
#  index_ai_agent_runs_on_user_id                          (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (ai_agent_id => ai_agents.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (parent_run_id => ai_agent_runs.id)
#  fk_rails_...  (user_id => users.id)
#

class AiAgentRun < ApplicationRecord
  belongs_to :ai_agent
  belongs_to :user
  belongs_to :organization
  belongs_to :invocable, polymorphic: true, optional: true
  belongs_to :parent_run, class_name: "AiAgentRun", optional: true
  has_many   :ai_agent_run_steps, -> { order(step_number: :asc) }, dependent: :destroy
  has_many   :ai_agent_feedbacks, dependent: :destroy
  has_many   :ai_agent_interactions, dependent: :destroy
  has_many   :child_runs, class_name: "AiAgentRun", foreign_key: :parent_run_id, dependent: :destroy
  has_one    :feedback_by_user, ->(run) { where(user_id: run.user_id) }, class_name: "AiAgentFeedback"

  enum :status, {
    pending:        0,
    running:        1,
    paused:         2,
    completed:      3,
    failed:         4,
    cancelled:      5,
    awaiting_input: 6
  }, prefix: true

  validates :ai_agent_id, :user_id, :organization_id, presence: true

  scope :recent,      -> { order(created_at: :desc) }
  scope :active,      -> { where(status: [ :pending, :running, :paused ]) }
  scope :for_context, ->(type, id) { where(invocable_type: type, invocable_id: id) }
  scope :by_agent,    ->(agent) { where(ai_agent: agent) }
  scope :by_user,     ->(user)  { where(user: user) }

  # State transition helpers
  def start!
    update!(status: :running, started_at: Time.current, last_activity_at: Time.current)
    Event.emit("agent_run.started", organization_id, user_id, {
      agent_id: ai_agent_id,
      run_id: id,
      trigger_source: trigger_source
    })
  end

  def complete!(summary: nil, data: {})
    update!(
      status: :completed,
      completed_at: Time.current,
      result_summary: summary,
      result_data: data,
      last_activity_at: Time.current
    )
    ai_agent.increment!(:success_count)
    ai_agent.increment!(:run_count)

    Event.emit("agent_run.completed", organization_id, user_id, {
      agent_id: ai_agent_id,
      run_id: id,
      summary: summary,
      trigger_source: trigger_source
    })
  end

  def fail!(error_message)
    update!(
      status: :failed,
      error_message: error_message,
      completed_at: Time.current,
      last_activity_at: Time.current
    )
    ai_agent.increment!(:run_count)

    Event.emit("agent_run.failed", organization_id, user_id, {
      agent_id: ai_agent_id,
      run_id: id,
      error: error_message,
      trigger_source: trigger_source
    })
  end

  def mark_awaiting_input!
    update!(status: :awaiting_input, awaiting_at: Time.current, last_activity_at: Time.current)
    Event.emit("agent_run.awaiting_input", organization_id, user_id, {
      agent_id: ai_agent_id,
      run_id: id
    })
  end

  def pause!
    update!(status: :paused, paused_at: Time.current, last_activity_at: Time.current)
    Event.emit("agent_run.paused", organization_id, user_id, {
      agent_id: ai_agent_id,
      run_id: id
    })
  end

  def cancel!(reason: nil)
    update!(
      status: :cancelled,
      cancellation_reason: reason,
      completed_at: Time.current,
      last_activity_at: Time.current
    )
    ai_agent.increment!(:run_count)

    Event.emit("agent_run.cancelled", organization_id, user_id, {
      agent_id: ai_agent_id,
      run_id: id,
      reason: reason
    })
  end

  def resume!
    update!(status: :running, paused_at: nil, last_activity_at: Time.current)
    Event.emit("agent_run.resumed", organization_id, user_id, {
      agent_id: ai_agent_id,
      run_id: id
    })
  end

  def touch_activity!
    update_column(:last_activity_at, Time.current)
end

  def turbo_channel
    "agent_run_#{id}"
  end

  def progress_percent
    return 0 if steps_total.zero?
    ((steps_completed.to_f / steps_total) * 100).round
  end

  def duration_seconds
    return nil unless started_at
    end_time = completed_at || Time.current
    (end_time - started_at).round
  end
end
