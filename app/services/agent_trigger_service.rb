class AgentTriggerService < ApplicationService
  # Unified service for all three agent trigger modes: manual, event, scheduled

  def self.trigger_manual(agent:, user:, input:, invocable: nil)
    instance = new
    instance.trigger_manual(agent: agent, user: user, input: input, invocable: invocable)
  end

  def self.trigger_from_event(agent:, event_type:, event_payload:, organization: nil)
    instance = new
    instance.trigger_from_event(agent: agent, event_type: event_type, event_payload: event_payload, organization: organization)
  end

  def self.trigger_from_schedule(agent:)
    instance = new
    instance.trigger_from_schedule(agent: agent)
  end

  def trigger_manual(agent:, user:, input:, invocable: nil)
    # Check budget
    budget_check = AgentTokenBudgetService.call(agent: agent, estimated_tokens: agent.max_tokens_per_run)
    return failure(message: budget_check.message) if budget_check.failure?

    # Create the run
    run = AiAgentRun.create!(
      ai_agent: agent,
      user: user,
      organization: user.organizations.first || agent.organization,
      user_input: input,
      invocable: invocable,
      trigger_source: "manual"
    )

    # If agent has pre_run_questions, move to awaiting_input state
    if agent.pre_run_questions.present?
      run.mark_awaiting_input!
      return success(data: { run: run, awaiting_input: true })
    end

    # Otherwise, enqueue the job
    AgentRunJob.perform_later(run.id)
    success(data: { run: run })
  rescue => e
    Rails.logger.error("Failed to trigger agent manually: #{e.message}")
    failure(message: "Failed to trigger agent: #{e.message}")
  end

  def trigger_from_event(agent:, event_type:, event_payload:, organization: nil)
    # Event-triggered runs have no specific user; use system or org owner
    user = agent.user || organization&.owner_user || User.first
    return failure(message: "No user available for event-triggered run") unless user

    organization ||= agent.organization || user.organizations.first
    return failure(message: "No organization context for event-triggered run") unless organization

    # Build input from event payload
    input = build_input_from_event(event_type, event_payload)

    # Get the invocable resource from the event if available
    invocable = extract_invocable_from_event(event_payload)

    # Check budget
    budget_check = AgentTokenBudgetService.call(agent: agent, estimated_tokens: agent.max_tokens_per_run)
    return failure(message: budget_check.message) if budget_check.failure?

    # Create the run
    run = AiAgentRun.create!(
      ai_agent: agent,
      user: user,
      organization: organization,
      user_input: input,
      invocable: invocable,
      trigger_source: "event",
      metadata: { event_type: event_type, event_payload: event_payload }
    )

    # Event-triggered runs skip pre_run_questions and go straight to execution
    AgentRunJob.perform_later(run.id)
    success(data: { run: run })
  rescue => e
    Rails.logger.error("Failed to trigger agent from event: #{e.message}")
    failure(message: "Failed to trigger agent from event: #{e.message}")
  end

  def trigger_from_schedule(agent:)
    # Scheduled runs have no specific user; use system user
    user = agent.user || agent.organization&.owner_user || User.first
    return failure(message: "No user available for scheduled run") unless user

    organization = agent.organization || user.organizations.first
    return failure(message: "No organization context for scheduled run") unless organization

    # Build input for the scheduled task
    input = "Scheduled execution of #{agent.name}"

    # Check budget
    budget_check = AgentTokenBudgetService.call(agent: agent, estimated_tokens: agent.max_tokens_per_run)
    return failure(message: budget_check.message) if budget_check.failure?

    # Create the run
    run = AiAgentRun.create!(
      ai_agent: agent,
      user: user,
      organization: organization,
      user_input: input,
      trigger_source: "schedule",
      metadata: { scheduled_at: Time.current }
    )

    # Scheduled runs skip pre_run_questions and go straight to execution
    AgentRunJob.perform_later(run.id)
    success(data: { run: run })
  rescue => e
    Rails.logger.error("Failed to trigger agent from schedule: #{e.message}")
    failure(message: "Failed to trigger agent from schedule: #{e.message}")
  end

  private

  def build_input_from_event(event_type, payload)
    case event_type
    when "list_item.completed"
      item = payload["item"]
      "List item completed: #{item['title']}"
    when "list_item.created"
      item = payload["item"]
      "New list item: #{item['title']}"
    when "list_item.updated"
      item = payload["item"]
      "List item updated: #{item['title']}"
    else
      "Event triggered: #{event_type}"
    end
  end

  def extract_invocable_from_event(payload)
    # Try to extract the resource from the event payload
    if payload["item_id"]
      ListItem.find_by(id: payload["item_id"])
    elsif payload["list_id"]
      List.find_by(id: payload["list_id"])
    end
  end
end
