# app/policies/chat_policy.rb
#
# Authorization policy for Chat resource
# Ensures users can only access chats they own

class ChatPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    owns_chat?
  end

  def create?
    user.present? && user.in_organization?(record.organization)
  end

  def create_message?
    owns_chat?
  end

  def destroy?
    owns_chat?
  end

  def archive?
    owns_chat?
  end

  def restore?
    owns_chat?
  end

  def save_and_create_new_chat?
    owns_chat?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.by_user(user).by_organization(user.current_organization)
    end
  end

  private

  def owns_chat?
    record.user_id == user.id && user.in_organization?(record.organization)
  end
end
