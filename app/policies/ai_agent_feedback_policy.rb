class AiAgentFeedbackPolicy < ApplicationPolicy
  def create?
    # User must be the runner of the associated run
    run = record.ai_agent_run
    run.user == user && run.completed?
  end

  class Scope < Scope
    def resolve
      scope.where(user_id: user.id)
    end
  end
end
