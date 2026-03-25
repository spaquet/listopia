class AiAgentPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def browse?
    user.present?
  end

  def my_agents?
    user.present?
  end

  def show?
    record.accessible_by?(user)
  end

  def create?
    # System agents can only be created by Listopia admin, never by regular users
    return false if record.scope_system_agent?

    # For user_agent: any authenticated user can create
    # For org/team agents: only org admin/owner can create
    return true if record.scope_user_agent?
    return false unless Current.organization && user.in_organization?(Current.organization)

    membership = Current.organization.membership_for(user)
    membership&.role.in?(%w[admin owner])
  end

  def update?
    record.manageable_by?(user)
  end

  def edit?
    update?
  end

  def destroy?
    record.manageable_by?(user)
  end

  def invoke?
    record.accessible_by?(user)
  end

  def runs?
    show?
  end

  class Scope < Scope
    def resolve
      system_agents = scope.system_level.available
      org_agents = resolved_org_agents
      team_agents = resolved_team_agents
      user_agents = resolved_user_agents

      scope.where(id: system_agents)
           .or(scope.where(id: org_agents))
           .or(scope.where(id: team_agents))
           .or(scope.where(id: user_agents))
    end

    private

    def resolved_org_agents
      return scope.none unless Current.organization
      scope.org_agent.for_organization(Current.organization).available
    end

    def resolved_team_agents
      return scope.none unless Current.organization
      user_team_ids = TeamMembership.where(user_id: user.id)
                                    .joins(:team)
                                    .where(teams: { organization_id: Current.organization.id })
                                    .pluck(:team_id)
      return scope.none if user_team_ids.empty?
      scope.team_agent.joins(:ai_agent_team_memberships)
           .where(ai_agent_team_memberships: { team_id: user_team_ids })
           .available
           .distinct
    end

    def resolved_user_agents
      scope.user_agent.for_user(user).kept
    end
  end
end
