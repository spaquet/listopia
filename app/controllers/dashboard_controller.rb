# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @my_lists = current_user.lists
                          .order(updated_at: :desc)
                          .limit(10)

    @collaborated_lists = current_user.collaborated_lists.includes(:owner)
                                    .order(updated_at: :desc)
                                    .limit(10)

    @recent_items = ListItem.joins(:list)
                          .where(list: current_user.accessible_lists)
                          .includes(:list)
                          .order(updated_at: :desc)
                          .limit(20)

    @stats = DashboardStatsService.new(current_user).call
  end
end
