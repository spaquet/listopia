class CommentPolicy < ApplicationPolicy
  # NOTE: Up to Pundit v2.3.1, the inheritance was declared as
  # `Scope < Scope` rather than `Scope < ApplicationPolicy::Scope`.
  # In most cases the behavior will be identical, but if updating existing
  # code, beware of possible changes to the ancestors:
  # https://gist.github.com/Burgestrand/4b4bc22f31c8a95c425fc0e30d7ef1f5

  class CommentPolicy < ApplicationPolicy
    def create?
      # Allow authenticated users to create comments on any accessible resource
      user.present?
    end

    def destroy?
      # Only comment author or admin can delete
      user == record.user || user.admin?
    end
  end
end
