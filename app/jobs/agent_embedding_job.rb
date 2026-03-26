class AgentEmbeddingJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 5.seconds, attempts: 2

  def perform(agent_id)
    agent = AiAgent.find(agent_id)
    return unless agent.requires_embedding_update?

    result = EmbeddingGenerationService.call(agent)

    if result.failure?
      Rails.logger.warn("Failed to generate embedding for agent #{agent.id}: #{result.message}")
    else
      Rails.logger.info("Successfully generated embedding for agent #{agent.id}")
    end
  end
end
