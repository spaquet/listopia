# app/controllers/list_items_controller.rb
class ListItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_list
  before_action :set_list_item, only: [ :show, :update, :destroy, :toggle_completion, :toggle_status ]
  before_action :authorize_list_access!

  def create
    @list_item = @list.list_items.build(list_item_params)

    if @list_item.save
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
    if @list_item.update(list_item_params)
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

  # Toggle completion status using the new status enum
  def toggle_completion
    new_status = @list_item.status_completed? ? :pending : :completed

    if @list_item.update(status: new_status)
      respond_to do |format|
        format.html { redirect_to @list }
        format.turbo_stream
        format.json { render json: @list_item }
      end
    else
      respond_to do |format|
        format.html { redirect_to @list, alert: "Unable to update item status." }
        format.turbo_stream { head :unprocessable_entity }
        format.json { render json: @list_item.errors, status: :unprocessable_entity }
      end
    end
  end

  def toggle_status
    new_status = @list_item.status_completed? ? :pending : :completed

    if @list_item.update(status: new_status)
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

    if @list_item.update(assigned_user_id: user_to_assign&.id)
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

  # Bulk operations
  def bulk_complete
    item_ids = params[:item_ids] || []
    items = @list.list_items.where(id: item_ids, status: :pending)

    completed_count = 0
    items.each do |item|
      if item.update(status: :completed)
        completed_count += 1
      end
    end

    respond_to do |format|
      format.html { redirect_to @list, notice: "#{completed_count} items marked as completed." }
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("progress-#{@list.id}", partial: "lists/progress", locals: { list: @list }),
          items.map { |item| turbo_stream.replace(item, partial: "list_items/list_item", locals: { list_item: item }) }
        ].flatten
      end
      format.json { render json: { completed_count: completed_count } }
    end
  end

  def bulk_update
    item_ids = params[:item_ids] || []
    updates = params[:updates] || {}

    items = @list.list_items.where(id: item_ids)
    updated_count = items.update_all(updates.permit(:status, :priority, :assigned_user_id))

    respond_to do |format|
      format.html { redirect_to @list, notice: "#{updated_count} items updated." }
      format.turbo_stream do
        items.reload
        render turbo_stream: [
          turbo_stream.replace("progress-#{@list.id}", partial: "lists/progress", locals: { list: @list }),
          items.map { |item| turbo_stream.replace(item, partial: "list_items/list_item", locals: { list_item: item }) }
        ].flatten
      end
      format.json { render json: { updated_count: updated_count } }
    end
  end

  private

  def set_list
    @list = List.find(params[:list_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to lists_path, alert: "List not found."
  end

  def set_list_item
    @list_item = @list.list_items.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to @list, alert: "Item not found."
  end

  def authorize_list_access!
    unless @list.readable_by?(current_user)
      redirect_to lists_path, alert: "You don't have permission to access this list."
    end
  end

  def list_item_params
    params.require(:list_item).permit(
      :title, :description, :item_type, :priority, :status,
      :due_date, :assigned_user_id, :url, :position,
      :estimated_duration, :duration_days, :start_date
    )
  end
end
