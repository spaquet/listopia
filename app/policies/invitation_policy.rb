# app/policies/invitation_policy.rb
class InvitationPolicy < ApplicationPolicy
  def create?
    case record.invitable_type
    when "List"
      record.invitable.owner == user
    else
      false
    end
  end

  def accept?
    record.email == user&.email
  end

  def destroy?
    case record.invitable_type
    when "List"
      record.invitable.owner == user || record.invited_by == user
    else
      false
    end
  end

  def resend?
    case record.invitable_type
    when "List"
      record.invitable.owner == user
    else
      false
    end
  end
end
