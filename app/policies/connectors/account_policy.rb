module Connectors
  # Policy for user-scoped connector accounts
  class AccountPolicy < ApplicationPolicy
    def index?
      user.present?
    end

    def show?
      record.user_id == user.id
    end

    def create?
      user.present?
    end

    def update?
      record.user_id == user.id
    end

    def destroy?
      record.user_id == user.id
    end

    def test?
      record.user_id == user.id
    end

    def pause?
      record.user_id == user.id
    end

    def resume?
      record.user_id == user.id
    end

    class Scope
      def initialize(user, scope)
        @user = user
        @scope = scope
      end

      def resolve
        return scope.none unless user.present?
        scope.where(user_id: user.id)
      end

      private

      attr_reader :user, :scope
    end
  end
end
