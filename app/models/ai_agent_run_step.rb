# == Schema Information
#
# Table name: ai_agent_run_steps
#
#  id                 :uuid             not null, primary key
#  completed_at       :datetime
#  description        :text
#  error_message      :text
#  input_tokens       :integer          default(0)
#  metadata           :jsonb            not null
#  output_tokens      :integer          default(0)
#  processing_time_ms :integer
#  prompt_sent        :text
#  response_received  :text
#  started_at         :datetime
#  status             :integer          default("pending"), not null
#  step_number        :integer          not null
#  step_type          :string           not null
#  title              :string
#  tool_input         :jsonb            not null
#  tool_name          :string
#  tool_output        :jsonb            not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  ai_agent_run_id    :uuid             not null
#
# Indexes
#
#  index_ai_agent_run_steps_on_ai_agent_run_id                  (ai_agent_run_id)
#  index_ai_agent_run_steps_on_ai_agent_run_id_and_step_number  (ai_agent_run_id,step_number) UNIQUE
#  index_ai_agent_run_steps_on_status                           (status)
#  index_ai_agent_run_steps_on_step_type                        (step_type)
#
# Foreign Keys
#
#  fk_rails_...  (ai_agent_run_id => ai_agent_runs.id)
#

class AiAgentRunStep < ApplicationRecord
  belongs_to :ai_agent_run

  STEP_TYPES = %w[
    llm_call tool_call resource_read resource_write
    user_interaction checkpoint error_recovery
  ].freeze

  enum :status, {
    pending:   0,
    running:   1,
    completed: 2,
    failed:    3,
    skipped:   4
  }, prefix: true

  validates :step_number, presence: true, uniqueness: { scope: :ai_agent_run_id }
  validates :step_type,   presence: true, inclusion: { in: STEP_TYPES }

  scope :completed, -> { where(status: :completed) }
  scope :failed,    -> { where(status: :failed) }

  def start!
    update!(status: :running, started_at: Time.current)
  end

  def complete!(output: {})
    update!(status: :completed, completed_at: Time.current, tool_output: output)
    ai_agent_run.increment!(:steps_completed)
    ai_agent_run.touch_activity!
  end

  def fail!(error)
    update!(status: :failed, error_message: error, completed_at: Time.current)
  end
end
