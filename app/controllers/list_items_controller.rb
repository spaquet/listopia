# app/controllers/list_items_controller.rb
class ListItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_list
  before_action :set_list_item, only: [ :show, :edit, :update, :destroy, :toggle_completion ]
  before_action :authorize_list_access!

  # Create a new list item
  def create
    @list_item = @list.list_items.build(list_item_params)

    if @list_item.save
      respond_with_turbo_stream do
        render :create
      end
    else
      respond_with_turbo_stream do
        render :form_errors
      end
    end
  end

  # Update an existing list item
  def update
    if @list_item.update(list_item_params)
      respond_with_turbo_stream do
        render :update
      end
    else
      respond_with_turbo_stream do
        render :form_errors
      end
    end
  end

  # Delete a list item
  def destroy
    @list_item.destroy

    respond_with_turbo_stream do
      render :destroy
    end
  end

  # Toggle completion status of a list item
  def toggle_completion
    @list_item.toggle_completion!

    respond_with_turbo_stream do
      render :toggle_completion
    end
  end

  # Bulk update list items (for reordering, bulk completion, etc.)
  def bulk_update
    case params[:action_type]
    when "reorder"
      update_positions
    when "bulk_complete"
      bulk_complete_items
    when "bulk_delete"
      bulk_delete_items
    end

    respond_with_turbo_stream do
      render :bulk_update
    end
  end

  private

  # Find the list ensuring user has access
  def set_list
    @list = current_user.accessible_lists.find(params[:list_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to lists_path, alert: "List not found."
  end

  # Find the list item within the current list
  def set_list_item
    @list_item = @list.list_items.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to @list, alert: "Item not found."
  end

  # Check if user can collaborate on this list
  def authorize_list_access!
    authorize_resource_access!(@list, :edit)
  end

  # Strong parameters for list item creation/update
  def list_item_params
    params.require(:list_item).permit(
      :title, :description, :item_type, :priority, :due_date,
      :reminder_at, :assigned_user_id, :url, :position, metadata: {}
    )
  end

  # Update positions for drag-and-drop reordering
  def update_positions
    params[:positions].each do |item_id, position|
      @list.list_items.find(item_id).update!(position: position.to_i)
    end
  end

  # Mark multiple items as completed
  def bulk_complete_items
    item_ids = params[:item_ids] || []
    @list.list_items.where(id: item_ids).update_all(
      completed: true,
      completed_at: Time.current
    )
  end

  # Delete multiple items
  def bulk_delete_items
    item_ids = params[:item_ids] || []
    @list.list_items.where(id: item_ids).destroy_all
  end
end
