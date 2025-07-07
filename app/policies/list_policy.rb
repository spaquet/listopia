# app/policies/list_policy.rb
class ListPolicy < ApplicationPolicy
  def index?
    true # All authenticated users can see the lists index
  end

  def show?
    return true if record.is_public?
    return true if record.owner == user

    record.readable_by?(user)
  end

  def create?
    user.present?
  end

  def update?
    return true if record.owner == user

    record.writable_by?(user)
  end

  def destroy?
    record.owner == user
  end

  def manage_collaborators?
    record.owner == user
  end

  def invite_collaborator?
    record.owner == user
  end

  class Scope < Scope
    def resolve
      if user
        scope.joins("LEFT JOIN collaborators ON lists.id = collaborators.collaboratable_id AND collaborators.collaboratable_type = 'List'")
            .where("lists.user_id = ? OR collaborators.user_id = ? OR lists.is_public = ?",
                    user.id, user.id, true)
            .group("lists.id")  # Use GROUP BY instead of DISTINCT
      else
        scope.where(is_public: true)
      end
    end
  end
end
