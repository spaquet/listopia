# frozen_string_literal: true

class TeamPolicy < ApplicationPolicy
  def index?
    user.in_organization?(record.organization)
  end

  def show?
    user.in_organization?(record.organization) && user_is_member?(record)
  end

  def create?
    user.in_organization?(record.organization) && user_can_manage_teams?(record.organization)
  end

  def update?
    user.in_organization?(record.organization) && user_can_manage_team?(record)
  end

  def edit?
    update?
  end

  def destroy?
    user.in_organization?(record.organization) && user_can_manage_team?(record)
  end

  def manage_members?
    user.in_organization?(record.organization) && user_can_manage_team?(record)
  end

  def add_member?
    manage_members?
  end

  def remove_member?
    manage_members?
  end

  def update_member_role?
    # Only admin/lead can change roles
    return false unless user.in_organization?(record.organization)

    role = record.user_role(user)
    role.in?(['admin', 'lead'])
  end

  # Scope for index action
  class Scope < Scope
    def resolve
      # Return teams in organizations the user is a member of
      scope.joins(:organization)
           .joins("INNER JOIN organization_memberships ON organizations.id = organization_memberships.organization_id")
           .where(organization_memberships: { user_id: user.id })
           .distinct
    end
  end

  private

  def user_is_member?(team)
    team.member?(user)
  end

  def user_can_manage_teams?(organization)
    membership = organization.membership_for(user)
    membership&.can_manage_teams? || false
  end

  def user_can_manage_team?(team)
    return false unless user.in_organization?(team.organization)

    role = team.user_role(user)
    role.in?(['admin', 'lead'])
  end
end
