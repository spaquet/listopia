# app/controllers/list_items_controller.rb
class ListItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_list
  before_action :set_list_item, only: [ :edit, :show, :update, :destroy, :toggle_completion ]
  before_action :authorize_list_access!

  # Create a new list item
  def create
    service = ListItemService.new(@list, current_user)
    result = service.create_item(**list_item_params.to_h.symbolize_keys)

    if result.success?
      @list_item = result.data
      @list.reload
      respond_with_turbo_stream { render :create }
    else
      @list_item = @list.list_items.build(list_item_params)
      @list_item.errors.add(:base, result.errors.join(", "))
      respond_with_turbo_stream { render :form_errors }
    end
  end

  def edit
    respond_to do |format|
      format.html {
        if turbo_frame_request?
          render "inline_edit_form", layout: false
        else
          redirect_to @list
        end
      }
    end
  end

  # Update an existing list item
  def update
    service = ListItemService.new(@list, current_user)
    result = service.update_item(@list_item.id, **list_item_params.to_h.symbolize_keys)

    if result.success?
      @list_item = result.data
      @list.reload
      respond_to do |format|
        format.html {
          if turbo_frame_request?
            render "item_display", layout: false
          else
            redirect_to @list, notice: "Item updated successfully!"
          end
        }
      end
    else
      respond_to do |format|
        format.html {
          if turbo_frame_request?
            @list_item.errors.add(:base, result.errors.join(", "))
            render "inline_edit_form", layout: false, status: :unprocessable_entity
          else
            redirect_to @list, alert: result.errors.join(", ")
          end
        }
      end
    end
  end

  # Delete a list item
  def destroy
    service = ListItemService.new(@list, current_user)
    result = service.delete_item(@list_item.id)

    if result.success?
      @item_id = @list_item.id
      @list.reload
      respond_to do |format|
        format.html {
          if turbo_frame_request?
            render "item_destroyed", layout: false
          else
            redirect_to @list, notice: "Item deleted successfully!"
          end
        }
      end
    else
      respond_to do |format|
        format.html {
          if turbo_frame_request?
            render plain: "Error: #{result.errors.join(', ')}", status: :unprocessable_entity
          else
            redirect_to @list, alert: result.errors.join(", ")
          end
        }
      end
    end
  end

  # Toggle completion status of a list item
  def toggle_completion
    service = ListItemService.new(@list, current_user)

    # Toggle the completion status
    new_completed = !@list_item.completed
    result = service.update_item(@list_item.id, completed: new_completed, completed_at: new_completed ? Time.current : nil)

    if result.success?
      @list_item = result.data
      @list.reload
      respond_with_turbo_stream { render :toggle_completion }
    else
      respond_with_turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "list_item_#{@list_item.id}",
          partial: "shared/error_message",
          locals: { message: result.errors.join(", ") }
        )
      end
    end
  end

  # Bulk update list items (for reordering, bulk completion, etc.)
  def bulk_update
    service = ListItemService.new(@list, current_user)

    case params[:action_type]
    when "reorder"
      result = service.reorder_items(params[:positions] || {})
    when "bulk_complete"
      result = service.bulk_complete_items(params[:item_ids] || [])
    when "bulk_delete"
      result = service.bulk_delete_items(params[:item_ids] || [])
    else
      result = ApplicationService::Result.failure(errors: "Unknown bulk action")
    end

    if result.success?
      @list.reload
      respond_with_turbo_stream { render :bulk_update }
    else
      respond_with_turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "flash-messages",
          partial: "shared/error_message",
          locals: { message: result.errors.join(", ") }
        )
      end
    end
  end

  def show
    respond_to do |format|
      format.turbo_stream { render :show }
      format.html { redirect_to @list }
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
      item = @list.list_items.find(item_id)
      item.skip_notifications = true # Avoid spamming notifications for reordering
      item.update!(position: position.to_i)
    end
  end

  # Mark multiple items as completed
  def bulk_complete_items
    item_ids = params[:item_ids] || []
    @list.list_items.where(id: item_ids).find_each do |item|
      item.skip_notifications = true # We'll send one bulk notification instead
      item.update!(completed: true, completed_at: Time.current)
    end

    # Send a single notification for bulk completion
    if item_ids.any? && Current.user
      NotificationService.new(Current.user)
                        .notify_item_activity(@list.list_items.first, "bulk_completed")
    end
  end

  # Delete multiple items
  def bulk_delete_items
    item_ids = params[:item_ids] || []
    items = @list.list_items.where(id: item_ids)
    items.find_each do |item|
      item.skip_notifications = true
    end
    items.destroy_all

    # Send a single notification for bulk deletion
    if item_ids.any? && Current.user
      NotificationService.new(Current.user)
                        .notify_item_activity(@list.list_items.build(title: "#{item_ids.count} items"), "bulk_deleted")
    end
  end
end
