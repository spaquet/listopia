# app/controllers/admin/lists_controller.rb
class Admin::ListsController < Admin::BaseController
  before_action :set_list, only: [ :show, :destroy ]

  def index
    @pagy, @lists = pagy(List.includes(:owner).order(created_at: :desc))
  end

  def show
  end

  def destroy
    @list.destroy
    redirect_to admin_lists_path, notice: "List deleted successfully."
  end

  private

  def set_list
    @list = List.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_lists_path, alert: "List not found."
  end
end
