class AiAgentRunPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    record.user == user || org_admin_or_owner?
  end

  def create?
    # Delegate to agent policy - can user invoke the agent?
    AiAgentPolicy.new(user, record.ai_agent).invoke?
  end

  def cancel?
    record.user == user || org_admin_or_owner?
  end

  def pause?
    record.user == user || org_admin_or_owner?
  end

  def resume?
    record.user == user || org_admin_or_owner?
  end

  class Scope < Scope
    def resolve
      if org_admin_or_owner?
        scope.where(organization_id: Current.organization&.id)
      else
        scope.where(user_id: user.id)
      end
    end

    private

    def org_admin_or_owner?
      return false unless Current.organization
      membership = Current.organization.membership_for(user)
      membership&.role.in?(%w[admin owner])
    end
  end

  private

  def org_admin_or_owner?
    return false unless Current.organization
    membership = Current.organization.membership_for(user)
    membership&.role.in?(%w[admin owner])
  end
end
