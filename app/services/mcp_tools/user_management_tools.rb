# app/services/mcp_tools/user_management_tools.rb
module McpTools
  class UserManagementTools
    attr_reader :user, :context

    def initialize(user, context = {})
      @user = user
      @context = context
    end

    # List users with optional filters
    def list_users(filters: {})
      return unauthorized_error unless user.admin?

      scope = User.all

      # Apply filters
      scope = scope.where(status: filters["status"]) if filters["status"]
      scope = scope.search_by_email(filters["email"]) if filters["email"].present?
      scope = scope.search_by_name(filters["name"]) if filters["name"].present?
      scope = scope.with_role(:admin) if filters["admin"] == true

      users = scope.order(created_at: :desc).limit(50)

      {
        success: true,
        users: users.map { |u| u.profile_summary(include_sensitive: true) },
        count: users.count,
        total_count: User.count
      }
    end

    # Get detailed user information
    def get_user(user_id:)
      target_user = find_user(user_id)
      return target_user if target_user[:success] == false

      target = target_user[:user]

      unless Pundit.policy(user, target).show?
        return unauthorized_error("Not authorized to view this user")
      end

      {
        success: true,
        user: target.profile_summary(include_sensitive: user.admin?),
        admin_audit_trail: user.admin? ? target.admin_audit_trail : nil
      }
    end

    # Update user profile
    def update_user(user_id:, **attributes)
      target_user = find_user(user_id)
      return target_user if target_user[:success] == false

      target = target_user[:user]

      unless Pundit.policy(user, target).update?
        return unauthorized_error("Not authorized to update this user")
      end

      # Filter attributes based on policy permissions
      policy = Pundit.policy(user, target)
      allowed_attrs = attributes.slice(*policy.permitted_attributes.map(&:to_s))

      if target.update(allowed_attrs)
        {
          success: true,
          message: "User updated successfully",
          user: target.profile_summary
        }
      else
        {
          success: false,
          errors: target.errors.full_messages
        }
      end
    end

    # Create a new user (admin only)
    def create_user(name:, email:, password:, make_admin: false)
      return unauthorized_error unless user.admin?

      new_user = User.new(
        name: name,
        email: email,
        password: password,
        password_confirmation: password,
        status: "active",
        email_verified_at: Time.current # Auto-verify admin-created users
      )

      if new_user.save
        new_user.make_admin! if make_admin

        {
          success: true,
          message: "User created successfully#{make_admin ? ' with admin privileges' : ''}",
          user: new_user.profile_summary
        }
      else
        {
          success: false,
          errors: new_user.errors.full_messages
        }
      end
    end

    # Delete user (admin only)
    def delete_user(user_id:)
      target_user = find_user(user_id)
      return target_user if target_user[:success] == false

      target = target_user[:user]

      unless Pundit.policy(user, target).destroy?
        return unauthorized_error("Not authorized to delete this user")
      end

      if target.destroy
        {
          success: true,
          message: "User deleted successfully"
        }
      else
        {
          success: false,
          errors: target.errors.full_messages
        }
      end
    end

    # Suspend user (admin only)
    def suspend_user(user_id:, reason: nil)
      target_user = find_user(user_id)
      return target_user if target_user[:success] == false

      target = target_user[:user]

      unless Pundit.policy(user, target).suspend?
        return unauthorized_error("Not authorized to suspend this user")
      end

      target.suspend!(reason: reason, suspended_by: user)

      {
        success: true,
        message: "User suspended successfully",
        user: target.profile_summary(include_sensitive: true)
      }
    end

    # Unsuspend user (admin only)
    def unsuspend_user(user_id:)
      target_user = find_user(user_id)
      return target_user if target_user[:success] == false

      target = target_user[:user]

      unless Pundit.policy(user, target).unsuspend?
        return unauthorized_error("Not authorized to unsuspend this user")
      end

      target.unsuspend!(unsuspended_by: user)

      {
        success: true,
        message: "User unsuspended successfully",
        user: target.profile_summary
      }
    end

    # Deactivate user (admin only)
    def deactivate_user(user_id:, reason: nil)
      target_user = find_user(user_id)
      return target_user if target_user[:success] == false

      target = target_user[:user]

      unless Pundit.policy(user, target).deactivate?
        return unauthorized_error("Not authorized to deactivate this user")
      end

      target.deactivate!(reason: reason, deactivated_by: user)

      {
        success: true,
        message: "User deactivated successfully",
        user: target.profile_summary(include_sensitive: true)
      }
    end

    # Reactivate user (admin only)
    def reactivate_user(user_id:)
      target_user = find_user(user_id)
      return target_user if target_user[:success] == false

      target = target_user[:user]

      unless Pundit.policy(user, target).reactivate?
        return unauthorized_error("Not authorized to reactivate this user")
      end

      target.reactivate!(reactivated_by: user)

      {
        success: true,
        message: "User reactivated successfully",
        user: target.profile_summary
      }
    end

    # Grant admin privileges (admin only)
    def grant_admin(user_id:)
      target_user = find_user(user_id)
      return target_user if target_user[:success] == false

      target = target_user[:user]

      unless Pundit.policy(user, target).grant_admin?
        return unauthorized_error("Not authorized to grant admin privileges")
      end

      target.make_admin!

      {
        success: true,
        message: "Admin privileges granted to #{target.name}",
        user: target.profile_summary
      }
    end

    # Revoke admin privileges (admin only)
    def revoke_admin(user_id:)
      target_user = find_user(user_id)
      return target_user if target_user[:success] == false

      target = target_user[:user]

      unless Pundit.policy(user, target).revoke_admin?
        return unauthorized_error("Not authorized to revoke admin privileges")
      end

      target.remove_admin!

      {
        success: true,
        message: "Admin privileges revoked from #{target.name}",
        user: target.profile_summary
      }
    end

    # Update admin notes (admin only)
    def update_user_notes(user_id:, notes:)
      return unauthorized_error unless user.admin?

      target_user = find_user(user_id)
      return target_user if target_user[:success] == false

      target = target_user[:user]
      target.update_admin_notes!(notes, updated_by: user)

      {
        success: true,
        message: "Admin notes updated successfully"
      }
    end

    # Get user statistics (admin only)
    def get_user_statistics
      return unauthorized_error unless user.admin?

      {
        success: true,
        statistics: {
          total_users: User.count,
          active_users: User.active_users.count,
          suspended_users: User.suspended_users.count,
          deactivated_users: User.deactivated_users.count,
          pending_verification: User.where(email_verified_at: nil).count,
          admin_users: User.with_role(:admin).count,
          users_signed_in_today: User.where("last_sign_in_at > ?", 24.hours.ago).count,
          users_signed_in_this_week: User.where("last_sign_in_at > ?", 1.week.ago).count
        }
      }
    end

    private

    def find_user(user_id)
      target = User.find_by(id: user_id)

      if target.nil?
        { success: false, error: "User not found" }
      else
        { success: true, user: target }
      end
    end

    def unauthorized_error(message = "Not authorized to perform this action")
      {
        success: false,
        error: message,
        unauthorized: true
      }
    end
  end
end
