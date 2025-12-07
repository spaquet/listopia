# app/policies/list_policy.rb
class ListPolicy < ApplicationPolicy
  def index?
    true # All authenticated users can see their lists
  end

  def show?
    # Check organization boundary first
    return false if record.organization_id.present? && !user.in_organization?(record.organization)

    # Owner, collaborators, or public lists
    record.owner == user ||
    record.collaborators.exists?(user: user) ||
    record.is_public?
  end

  def create?
    true # All authenticated users can create lists
  end

  def update?
    # Check organization boundary first
    return false if record.organization_id.present? && !user.in_organization?(record.organization)

    # Owner or write collaborators
    record.owner == user ||
    record.collaborators.permission_write.exists?(user: user)
  end

  def edit?
    update?
  end

  def destroy?
    # Check organization boundary first
    return false if record.organization_id.present? && !user.in_organization?(record.organization)

    # Only the owner can delete a list
    record.owner == user
  end

  def share?
    # Owner or write collaborators can share
    record.owner == user ||
    record.collaborators.permission_write.exists?(user: user)
  end

  def manage_collaborators?
    # Owner can always manage collaborators
    return true if record.owner == user

    # Write collaborators with can_invite_collaborators role can manage collaborators
    collaborator = record.collaborators.find_by(user: user)
    return true if collaborator&.permission_write? && collaborator&.has_role?(:can_invite_collaborators)

    false
  end

  def duplicate?
    show? # Anyone who can view can duplicate
  end

  def toggle_status?
    update? # Same as update permissions
  end

  def toggle_public_access?
    record.owner == user # Only owner can toggle public access
  end

  def kanban?
    show? # Same permissions as show - can view in kanban if can view in list view
  end

  # Scope for index action
  class Scope < Scope
    def resolve
      # Get user's active organization IDs
      user_org_ids = user.organization_memberships
                         .where(status: :active)
                         .pluck(:organization_id)

      # Lists in user's organizations where user is owner or collaborator
      org_lists_ids = List.where(organization_id: user_org_ids)
                          .where("user_id = ? OR id IN (SELECT collaboratable_id FROM collaborators WHERE collaboratable_type = 'List' AND user_id = ?)", user.id, user.id)
                          .select(:id)
                          .distinct

      # Personal lists owned by user
      personal_lists_ids = scope.where(organization_id: nil, user_id: user.id).select(:id)

      # Combine both queries
      scope.where("lists.id IN (?) OR lists.id IN (?)", org_lists_ids, personal_lists_ids)
    end
  end

  private

  def user_permission(list, user)
    return :owner if list.owner == user
    return :public_write if list.is_public? && list.public_permission_public_write?
    return :public_read if list.is_public?

    collaborator = list.collaborators.find_by(user: user)
    return :none unless collaborator

    collaborator.permission_write? ? :write : :read
  end
end
