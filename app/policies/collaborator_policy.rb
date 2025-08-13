# app/policies/collaborator_policy.rb
class CollaboratorPolicy < ApplicationPolicy
  def index?
    list_owner? || collaborator?
  end

  def create?
    list_owner?
  end

  def update?
    list_owner?
  end

  def destroy?
    list_owner? || own_collaboration?
  end

  private

  def list_owner?
    case record.collaboratable_type
    when "List"
      record.collaboratable.owner == user
    else
      false
    end
  end

  def collaborator?
    record.user == user
  end

  def own_collaboration?
    record.user == user
  end
end
