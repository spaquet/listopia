# app/controllers/list_items_controller.rb - Context tracking integration
class ListItemsController < ApplicationController
  include ContextTracking  # NEW: Include context tracking

  before_action :authenticate_user!
  before_action :set_list
  before_action :set_list_item, only: [:show, :edit, :update, :destroy, :complete, :toggle_status]
  before_action :authorize_list_access!

  def create
    @list_item = @list.list_items.build(list_item_params)

    if @list_item.save
      # NEW: Track item creation with rich context
      track_entity_action("item_added", @list_item, {
        list_id: @list.id,
        list_title: @list.title,
        priority: @list_item.priority,
        assigned_user_id: @list_item.assigned_user_id,
        position: @list_item.position,
        creation_method: params[:creation_method] || "manual"
      })

      respond_to do |format|
        format.html { redirect_to @list, notice: "Item was successfully added." }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.append("list-items-#{@list.id}", partial: "list_items/list_item", locals: { list_item: @list_item }),
            turbo_stream.replace("new_item_form_#{@list.id}", partial: "list_items/new_form", locals: { list: @list, list_item: @list.list_items.build }),
            turbo_stream.replace("progress-#{@list.id}", partial: "lists/progress", locals: { list: @list })
          ]
        end
        format.json { render json: @list_item, status: :created }
      end
    else
      respond_to do |format|
        format.html { redirect_to @list, alert: "Unable to add item." }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("new_item_form_#{@list.id}", partial: "list_items/new_form", locals: { list: @list, list_item: @list_item }) }
        format.json { render json: @list_item.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    previous_status = @list_item.status
    previous_assigned_user_id = @list_item.assigned_user_id

    if @list_item.update(list_item_params)
      # NEW: Track item updates with detailed change information
      changes = @list_item.previous_changes.except("updated_at")
      track_entity_action("item_updated", @list_item, {
        list_id: @list.id,
        changes: changes.keys,
        status_changed: changes.key?("status"),
        assignment_changed: changes.key?("assigned_user_id"),
        previous_status: previous_status,
        previous_assigned_user_id: previous_assigned_user_id,
        update_source: params[:source] || "manual"
      })

      respond_to do |format|
        format.html { redirect_to @list, notice: "Item was successfully updated." }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(@list_item, partial: "list_items/list_item", locals: { list_item: @list_item }),
            turbo_stream.replace("progress-#{@list.id}", partial: "lists/progress", locals: { list: @list })
          ]
        end
        format.json { render json: @list_item }
      end
    else
      respond_to do |format|
        format.html { redirect_to @list, alert: "Unable to update item." }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("edit_item_#{@list_item.id}", partial: "list_items/edit_form", locals: { list_item: @list_item }) }
        format.json { render json: @list_item.errors, status: :unprocessable_entity }
      end
    end
  end

  def toggle_status
    new_status = @list_item.completed? ? "pending" : "completed"
    previous_status = @list_item.status

    if @list_item.update(status: new_status)
      # NEW: Track status changes with completion context
      action = new_status == "completed" ? "item_completed" : "item_uncompleted"
      track_entity_action(action, @list_item, {
        list_id: @list.id,
        previous_status: previous_status,
        completion_method: params[:method] || "toggle",
        completed_at: new_status == "completed" ? Time.current : nil
      })

      respond_to do |format|
        format.html { redirect_to @list }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(@list_item, partial: "list_items/list_item", locals: { list_item: @list_item }),
            turbo_stream.replace("progress-#{@list.id}", partial: "lists/progress", locals: { list: @list })
          ]
        end
        format.json { render json: @list_item }
      end
    else
      respond_to do |format|
        format.html { redirect_to @list, alert: "Unable to update item status." }
        format.json { render json: @list_item.errors, status: :unprocessable_entity }
      end
    end
  end

  def assign
    user_to_assign = User.find_by(id: params[:user_id])
    previous_assigned_user_id = @list_item.assigned_user_id

    if @list_item.update(assigned_user_id: user_to_assign&.id)
      # NEW: Track assignment changes
      track_entity_action("item_assigned", @list_item, {
        list_id: @list.id,
        assigned_to_user_id: user_to_assign&.id,
        assigned_to_name: user_to_assign&.name,
        previous_assigned_user_id: previous_assigned_user_id,
        assignment_method: params[:method] || "manual"
      })

      respond_to do |format|
        format.html { redirect_to @list, notice: "Item assignment updated." }
        format.turbo_stream { render turbo_stream: turbo_stream.replace(@list_item, partial: "list_items/list_item", locals: { list_item: @list_item }) }
        format.json { render json: @list_item }
      end
    else
      respond_to do |format|
        format.html { redirect_to @list, alert: "Unable to assign item." }
        format.json { render json: @list_item.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    item_data = {
      title: @list_item.title,
      status: @list_item.status,
      list_id: @list.id,
      position: @list_item.position
    }

    @list_item.destroy!

    # Track item deletion
    track_action("item_deleted", @list_item, item_data.merge(
      deletion_source: params[:source] || "manual"
    ))

    respond_to do |format|
      format.html { redirect_to @list, notice: "Item was successfully deleted." }
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove(@list_item),
          turbo_stream.replace("progress-#{@list.id}", partial: "lists/progress", locals: { list: @list })
        ]
      end
      format.json { head :no_content }
    end
  end

  # Bulk operations with context tracking
  def bulk_complete
    item_ids = params[:item_ids] || []
    items = @list.list_items.where(id: item_ids, status: "pending")

    completed_count = 0
    items.each do |item|
      if item.update(status: "completed")
        completed_count += 1
        track_entity_action("item_completed", item, {
          list_id: @list.id,
          bulk_operation: true,
          bulk_operation_id: SecureRandom.uuid
        })
      end
    end

    respond_to do |format|
      format.html { redirect_to @list, notice: "#{completed_count} items marked as completed." }
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("list-items-#{@list.id}", partial: "list_items/items_list", locals: { list: @list }),
          turbo_stream.replace("progress-#{@list.id}", partial: "lists/progress", locals: { list: @list })
        ]
      end
      format.json { render json: { completed_count: completed_count } }
    end
  end

  private

  def set_list
    @list = List.find(params[:list_id])
  end

  def set_list_item
    @list_item = @list.list_items.find(params[:id])
  end

  def authorize_list_access!
    unless @list.writable_by?(current_user)
      redirect_to lists_path, alert: "You do not have permission to modify this list."
    end
  end

  def list_item_params
    params.require(:list_item).permit(:title, :description, :priority, :status, :due_date, :assigned_user_id)
  end
end
