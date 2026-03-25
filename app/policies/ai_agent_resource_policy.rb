class AiAgentResourcePolicy < ApplicationPolicy
  def create?
    record.ai_agent.manageable_by?(user)
  end

  def update?
    record.ai_agent.manageable_by?(user)
  end

  def destroy?
    record.ai_agent.manageable_by?(user)
  end

  def edit?
    update?
  end
end
