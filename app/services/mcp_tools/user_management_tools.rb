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
      organization_id = @context[:organization_id]
      return unauthorized_error("No organization context provided") unless organization_id.present?

      # Check if user is admin in this organization
      org_membership = user.organization_memberships.find_by(organization_id: organization_id)
      return unauthorized_error unless org_membership&.can_manage_members?

      # Scope to organization members only
      scope = User.joins(:organization_memberships)
                  .where(organization_memberships: { organization_id: organization_id })
                  .distinct

      # Apply filters
      scope = scope.where(status: filters["status"]) if filters["status"]
      scope = scope.search_by_email(filters["email"]) if filters["email"].present?
      scope = scope.search_by_name(filters["name"]) if filters["name"].present?

      users = scope.order(created_at: :desc).limit(50)
      total_in_org = User.joins(:organization_memberships)
                         .where(organization_memberships: { organization_id: organization_id })
                         .distinct.count

      {
        success: true,
        users: users.map { |u| u.profile_summary(include_sensitive: true) },
        count: users.count,
        total_count: total_in_org
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
      organization_id = @context[:organization_id]
      return unauthorized_error("No organization context provided") unless organization_id.present?

      # Check if user is admin in this organization
      org_membership = user.organization_memberships.find_by(organization_id: organization_id)
      return unauthorized_error unless org_membership&.can_manage_members?

      new_user = User.new(
        name: name,
        email: email,
        password: password,
        password_confirmation: password,
        status: "active",
        email_verified_at: Time.current # Auto-verify admin-created users
      )

      if new_user.save
        # Create organization membership for the new user
        organization = Organization.find(organization_id)
        OrganizationMembership.create!(
          user: new_user,
          organization: organization,
          role: make_admin ? "admin" : "member",
          status: "active"
        )

        new_user.make_admin! if make_admin

        {
          success: true,
          message: "User created successfully#{make_admin ? ' with admin privileges' : ''} and added to organization",
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
      organization_id = @context[:organization_id]
      return unauthorized_error("No organization context provided") unless organization_id.present?

      org_membership = user.organization_memberships.find_by(organization_id: organization_id)
      return unauthorized_error unless org_membership&.can_manage_members?

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
      organization_id = @context[:organization_id]
      return unauthorized_error("No organization context provided") unless organization_id.present?

      # Check if user is admin in this organization
      org_membership = user.organization_memberships.find_by(organization_id: organization_id)
      return unauthorized_error unless org_membership&.can_manage_members?

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
      organization_id = @context[:organization_id]
      return unauthorized_error("No organization context provided") unless organization_id.present?

      org_membership = user.organization_memberships.find_by(organization_id: organization_id)
      return unauthorized_error unless org_membership&.can_manage_members?

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
      organization_id = @context[:organization_id]
      return unauthorized_error("No organization context provided") unless organization_id.present?

      org_membership = user.organization_memberships.find_by(organization_id: organization_id)
      return unauthorized_error unless org_membership&.can_manage_members?

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
      organization_id = @context[:organization_id]
      return unauthorized_error("No organization context provided") unless organization_id.present?

      org_membership = user.organization_memberships.find_by(organization_id: organization_id)
      return unauthorized_error unless org_membership&.can_manage_members?

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
      organization_id = @context[:organization_id]
      return unauthorized_error("No organization context provided") unless organization_id.present?

      org_membership = user.organization_memberships.find_by(organization_id: organization_id)
      return unauthorized_error unless org_membership&.can_manage_members?

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
      organization_id = @context[:organization_id]
      return unauthorized_error("No organization context provided") unless organization_id.present?

      org_membership = user.organization_memberships.find_by(organization_id: organization_id)
      return unauthorized_error unless org_membership&.can_manage_members?

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
      organization_id = @context[:organization_id]
      return unauthorized_error("No organization context provided") unless organization_id.present?

      org_membership = user.organization_memberships.find_by(organization_id: organization_id)
      return unauthorized_error unless org_membership&.can_manage_members?

      # Scope statistics to organization
      org_users = User.joins(:organization_memberships)
                      .where(organization_memberships: { organization_id: organization_id })
                      .distinct

      {
        success: true,
        statistics: {
          total_users: org_users.count,
          active_users: org_users.where(status: "active").count,
          suspended_users: org_users.where(status: "suspended").count,
          deactivated_users: org_users.where(status: "deactivated").count,
          pending_verification: org_users.where(email_verified_at: nil).count,
          admin_users: org_users.with_role(:admin).count,
          users_signed_in_today: org_users.where("last_sign_in_at > ?", 24.hours.ago).count,
          users_signed_in_this_week: org_users.where("last_sign_in_at > ?", 1.week.ago).count
        }
      }
    end

    private

    def find_user(user_id)
      target = User.find_by(id: user_id)

      if target.nil?
        return { success: false, error: "User not found" }
      end

      # Check organization boundary
      organization_id = @context[:organization_id]
      if organization_id.present?
        unless target.organization_memberships.exists?(organization_id: organization_id)
          return { success: false, error: "User not found in this organization" }
        end
      end

      { success: true, user: target }
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
