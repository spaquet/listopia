class AgentScheduleJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: 0  # Don't retry this job

  def perform
    # Find all active agents with schedule triggers
    scheduled_agents = AiAgent.active.kept.with_trigger_type("schedule")

    scheduled_agents.each do |agent|
      dispatch_if_due(agent)
    end

    Rails.logger.debug("AgentScheduleJob: Checked #{scheduled_agents.count} scheduled agents")
  end

  private

  def dispatch_if_due(agent)
    trigger_config = agent.trigger_config || {}
    cron_expr = trigger_config["cron"]

    return unless cron_expr.present?

    # Parse and evaluate the cron expression
    if should_run_now?(cron_expr)
      result = AgentTriggerService.trigger_from_schedule(agent: agent)

      if result.failure?
        Rails.logger.warn("Failed to trigger scheduled agent #{agent.id}: #{result.message}")
      else
        Rails.logger.info("Triggered scheduled agent: #{agent.name}")
      end
    end
  end

  def should_run_now?(cron_expr)
    # Use Fugit to parse and evaluate cron expression
    # Fugit is commonly used with Solid Queue
    cron = Fugit.parse_cron(cron_expr)
    return false unless cron

    # Check if the cron should run at this minute
    now = Time.current
    cron.match?(now) || cron.match_bsec?(now)
  rescue => e
    Rails.logger.error("Failed to parse cron expression '#{cron_expr}': #{e.message}")
    false
  end
end
