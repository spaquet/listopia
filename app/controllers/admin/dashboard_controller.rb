# app/controllers/admin/dashboard_controller.rb
class Admin::DashboardController < Admin::BaseController
  def index
    org_users = current_organization.users
    org_memberships = current_organization.organization_memberships

    @stats = {
      total_users: org_users.count,
      active_users: org_users.where(status: "active").count,
      admin_users: org_memberships.where(role: [ :admin, :owner ]).count,
      new_users_this_month: org_users.where("users.created_at >= ?", Time.current.beginning_of_month).count
    }
  end
end
