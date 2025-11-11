# app/policies/comment_policy.rb
class CommentPolicy < ApplicationPolicy
  def create?
    # Allow if user can comment on the commentable resource
    user.present? && can_comment_on_commentable?
  end

  def destroy?
    # Comment author or list/item owner can delete
    record.user == user || is_owner_of_commentable?
  end

  def update?
    # For now, same as destroy (can extend later)
    destroy?
  end

  private

  def can_comment_on_commentable?
    case record.commentable
    when List
      commentable_policy = ListPolicy.new(user, record.commentable)
      # Owner and any collaborator (read or write) can comment
      record.commentable.owner == user ||
      record.commentable.collaborators.exists?(user: user)
    when ListItem
      commentable_policy = ListItemPolicy.new(user, record.commentable)
      # Owner and any collaborator can comment on list items
      record.commentable.list.owner == user ||
      record.commentable.list.collaborators.exists?(user: user)
    else
      false
    end
  end

  def is_owner_of_commentable?
    case record.commentable
    when List
      record.commentable.owner == user
    when ListItem
      record.commentable.list.owner == user
    else
      false
    end
  end
end
