# app/policies/user_policy.rb
class UserPolicy < ApplicationPolicy
  # User viewing their own settings page
  def settings?
    record == user
  end

  # Admin can view user list
  def index?
    user.admin?
  end

  # Users can view their own profile, admins can view any profile
  def show?
    user.admin? || record == user
  end

  # Users can edit their own profile, admins can edit any profile
  def edit?
    update?
  end

  # Users can update their own profile, admins can update any profile
  def update?
    user.admin? || record == user
  end

  # Users can change their own password
  def update_password?
    record == user
  end

  # Users can update their own preferences
  def update_preferences?
    record == user
  end

  # Users can update their own notification settings
  def update_notification_settings?
    record == user
  end

  # Only admins can delete users, and they cannot delete themselves
  def destroy?
    user.admin? && record != user
  end

  # Only admins can suspend users, and they cannot suspend themselves
  def suspend?
    user.admin? && record != user && record.active?
  end

  # Only admins can unsuspend users
  def unsuspend?
    user.admin? && record.suspended?
  end

  # Only admins can deactivate users, and they cannot deactivate themselves
  def deactivate?
    user.admin? && record != user && record.active?
  end

  # Only admins can reactivate users
  def reactivate?
    user.admin? && record.deactivated?
  end

  # Only admins can grant admin privileges, and they cannot grant to themselves
  def grant_admin?
    user.admin? && record != user && !record.admin?
  end

  # Only admins can revoke admin privileges, and they cannot revoke from themselves
  def revoke_admin?
    user.admin? && record != user && record.admin?
  end

  # Admin can create users
  def create?
    user.admin?
  end

  # Admin can toggle admin status
  def toggle_admin?
    user.admin? && record != user
  end

  # Admin can toggle user status (suspend/unsuspend)
  def toggle_status?
    user.admin? && record != user
  end

  # Define which attributes can be updated based on user role
  def permitted_attributes
    if user.admin?
      # Admins can update more fields
      [
        :name,
        :email,
        :bio,
        :avatar_url,
        :locale,
        :timezone,
        :status,
        :admin_notes
      ]
    elsif record == user
      # Regular users can only update their own basic profile fields
      [
        :name,
        :bio,
        :avatar_url,
        :locale,
        :timezone
      ]
    else
      []
    end
  end

  # Scope for index action - admins see all users, regular users see only themselves
  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin?
        scope.all
      else
        scope.where(id: user.id)
      end
    end
  end
end
