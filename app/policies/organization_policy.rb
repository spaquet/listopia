# frozen_string_literal: true

class OrganizationPolicy < ApplicationPolicy
  def index?
    true # All authenticated users can see their organizations
  end

  def show?
    user.in_organization?(record)
  end

  def create?
    true # All authenticated users can create organizations
  end

  def update?
    user_can_manage?(record)
  end

  def edit?
    update?
  end

  def destroy?
    # Only owner can delete organization
    record.user_is_owner?(user)
  end

  def manage_members?
    user_can_manage?(record)
  end

  def invite_member?
    user_can_manage?(record)
  end

  def remove_member?
    user_can_manage?(record)
  end

  def update_member_role?
    # Only owner can change admin/owner roles
    return true if record.user_is_owner?(user)

    # Admins can change member roles
    return true if record.user_is_admin?(user)

    false
  end

  def manage_teams?
    user_can_manage?(record)
  end

  def view_audit_logs?
    user_can_manage?(record)
  end

  def suspend?
    record.user_is_owner?(user)
  end

  def reactivate?
    record.user_is_owner?(user)
  end

  # Scope for index action
  class Scope < Scope
    def resolve
      # Return only organizations the user is a member of
      scope.joins(:organization_memberships)
           .where(organization_memberships: { user_id: user.id })
           .distinct
    end
  end

  private

  def user_can_manage?(organization)
    return false unless user.in_organization?(organization)

    # Owner or admin can manage
    role = organization.user_role(user)
    role.in?(['owner', 'admin'])
  end
end
