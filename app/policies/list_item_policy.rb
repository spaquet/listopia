# app/policies/list_item_policy.rb
# NOTE: Up to Pundit v2.3.1, the inheritance was declared as
# `Scope < Scope` rather than `Scope < ApplicationPolicy::Scope`.
# In most cases the behavior will be identical, but if updating existing
# code, beware of possible changes to the ancestors:
# https://gist.github.com/Burgestrand/4b4bc22f31c8a95c425fc0e30d7ef1f5

class ListItemPolicy < ApplicationPolicy
  attr_reader :list_item

  def initialize(user, list_item)
    super(user, list_item)
    @list_item = list_item
  end

  def show?
    list_readable?
  end

  def edit?
    list_writable?
  end

  def update?
    list_writable?
  end

  def create?
    list_writable?
  end

  def destroy?
    list_writable?
  end

  def toggle_completion?
    list_writable?
  end

  def toggle_status?
    list_writable?
  end

  def assign?
    list_writable?
  end

  def manage_collaborators?
    # Owner of the list can always manage collaborators on any item
    return true if list_item.list.owner == user

    # User assigned to this item can manage collaborators on it
    return true if list_item.assigned_user == user

    false
  end

  private

  def list_readable?
    # Owner, list collaborators, item collaborators, or public lists
    return true if list_item.list.readable_by?(user)
    return true if list_item.collaborators.exists?(user: user)
    false
  end

  def list_writable?
    # Owner of the list
    return true if list_item.list.owner == user

    # List-level write permission
    return true if list_item.list.writable_by?(user)

    # Item-level write permission
    return true if list_item.collaborators.permission_write.exists?(user: user)

    # Assigned user can update their own item
    return true if list_item.assigned_user_id == user.id

    false
  end
end
