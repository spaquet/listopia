class AgentRunJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 5.seconds, attempts: 2
  discard_on ActiveJob::DeserializationError

  def perform(agent_run_id)
    run = AiAgentRun.find(agent_run_id)

    if run.completed? || run.failed? || run.cancelled?
      Rails.logger.warn("AgentRunJob: Run #{agent_run_id} is already in terminal state #{run.status}")
      return
    end

    Rails.logger.info("AgentRunJob: Starting run #{agent_run_id} for agent #{run.ai_agent_id}")

    result = AgentExecutionService.call(agent_run: run)

    if result.failure?
      Rails.logger.error("AgentRunJob: Execution failed for run #{agent_run_id}: #{result.message}")
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error("AgentRunJob: AiAgentRun #{agent_run_id} not found")
  rescue => e
    Rails.logger.error("AgentRunJob: Unexpected error: #{e.class} - #{e.message}")
    run = AiAgentRun.find_by(id: agent_run_id)
    run&.fail!("Unexpected job error: #{e.message}")
    raise
  end
end
