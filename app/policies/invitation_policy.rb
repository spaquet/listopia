# app/policies/invitation_policy.rb
class InvitationPolicy < ApplicationPolicy
  def create?
    case record.invitable_type
    when "List"
      # Owner or write collaborators with can_invite_collaborators role
      return true if record.invitable.owner == user

      collaborator = record.invitable.collaborators.find_by(user: user)
      return true if collaborator&.permission_write? && collaborator&.has_role?(:can_invite_collaborators)

      false
    when "ListItem"
      # List owner or item collaborators with can_invite_collaborators role
      return true if record.invitable.list.owner == user

      list_collaborator = record.invitable.list.collaborators.find_by(user: user)
      return true if list_collaborator&.permission_write? && list_collaborator&.has_role?(:can_invite_collaborators)

      item_collaborator = record.invitable.collaborators.find_by(user: user)
      return true if item_collaborator&.permission_write? && item_collaborator&.has_role?(:can_invite_collaborators)

      false
    else
      false
    end
  end

  def accept?
    record.email == user&.email
  end

  def show?
    # Anyone can view an invitation if they have the token
    true
  end

  def destroy?
    case record.invitable_type
    when "List"
      record.invitable.owner == user || record.invited_by == user
    when "ListItem"
      record.invitable.list.owner == user || record.invited_by == user
    else
      false
    end
  end

  def resend?
    case record.invitable_type
    when "List"
      # Owner or the person who sent the invitation
      record.invitable.owner == user || record.invited_by == user
    when "ListItem"
      # List owner or the person who sent the invitation
      record.invitable.list.owner == user || record.invited_by == user
    else
      false
    end
  end

  def index?
    # Users can view their own invitations (sent and received)
    true
  end

  def decline?
    # Only the recipient can decline their own invitation
    record.email == user&.email && record.status == "pending"
  end

  def revoke?
    # Only the person who sent the invitation can revoke it
    record.invited_by == user && record.status == "pending"
  end

  def update?
    # Only the person who sent the invitation can update it
    record.invited_by == user && record.status == "pending"
  end
end
