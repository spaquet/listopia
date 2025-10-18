# app/controllers/admin/dashboard_controller.rb
class Admin::DashboardController < Admin::BaseController
  def index
    @stats = {
      total_users: User.count,
      active_users: User.where(status: "active").count,
      admin_users: User.with_role(:admin).count,
      new_users_this_month: User.where("created_at >= ?", Time.current.beginning_of_month).count
    }
  end
end
