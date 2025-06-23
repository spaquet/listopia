# app/controllers/public_lists_controller.rb
class PublicListsController < ApplicationController
  skip_before_action :authenticate_user!
  before_action :set_list

  def show
    @list_items = @list.list_items.includes(:assigned_user)
                      .order(:position, :created_at)
  end

  private

  def set_list
    @list = List.find_by!(public_slug: params[:slug], is_public: true)
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "List not found or not publicly available."
  end
end
