class AgentEventDispatchJob < ApplicationJob
  queue_as :default

  def perform(event_type, event_payload)
    # Find all active agents that are triggered by this event type
    matching_agents = AiAgent.status_active.kept.with_event_trigger(event_type)

    matching_agents.each do |agent|
      dispatch_to_agent(agent, event_type, event_payload)
    end

    Rails.logger.info("AgentEventDispatchJob: Dispatched #{event_type} to #{matching_agents.count} agents")
  end

  private

  def dispatch_to_agent(agent, event_type, event_payload)
    # Determine organization context
    organization = agent.organization || extract_organization_from_payload(event_payload)
    return unless organization

    # Trigger the agent from the event
    result = AgentTriggerService.trigger_from_event(
      agent: agent,
      event_type: event_type,
      event_payload: event_payload,
      organization: organization
    )

    if result.failure?
      Rails.logger.warn("Failed to dispatch #{event_type} to agent #{agent.id}: #{result.message}")
    else
      Rails.logger.debug("Successfully dispatched #{event_type} to agent #{agent.id}")
    end
  end

  def extract_organization_from_payload(payload)
    # Try to find organization from the event payload
    if payload["organization_id"]
      Organization.find_by(id: payload["organization_id"])
    elsif payload["item"]
      item = ListItem.find_by(id: payload["item"]["id"])
      item&.list&.organization
    elsif payload["list"]
      List.find_by(id: payload["list"]["id"])&.organization
    end
  end
end
