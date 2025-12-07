# app/controllers/list_items_controller.rb
class ListItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_list
  before_action :set_list_item, only: [ :show, :edit, :update, :destroy, :toggle_completion, :toggle_status, :share, :visit_url ]
  before_action :authorize_list_access!

  def create
    @list_item = @list.list_items.build(list_item_params)
    # Remove any explicit position setting - let the model callback handle it

    if @list_item.save
      respond_to do |format|
        format.html { redirect_to @list, notice: "Item was successfully added." }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("list-items", partial: "list_items/items_list", locals: { list_items: @list.list_items.order(:position, :created_at), list: @list }),
            turbo_stream.replace("new_list_item", partial: "list_items/quick_add_form", locals: { list: @list, list_item: @list.list_items.build }),
            turbo_stream.replace("list-stats", partial: "shared/list_stats", locals: { list: @list })
          ]
        end
        format.json { render json: @list_item, status: :created }
      end
    else
      respond_to do |format|
        format.html { redirect_to @list, alert: "Unable to add item." }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("new_list_item", partial: "list_items/quick_add_form", locals: { list: @list, list_item: @list_item }), status: :unprocessable_entity }
        format.json { render json: @list_item.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    if @list_item.update(list_item_params)
      # Reload list associations to get fresh count data for stats
      @list.reload

      respond_to do |format|
        format.html { redirect_to list_list_item_path(@list, @list_item), notice: "Item was successfully updated." }
        format.turbo_stream # Renders update.turbo_stream.erb
        format.json { render json: @list_item }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("list_item_#{@list_item.id}", partial: "list_items/item", locals: { item: @list_item, list: @list }) }
        format.json { render json: @list_item.errors, status: :unprocessable_entity }
      end
    end
  end

  # Add this action after the `edit` action
  def inline_update
    authorize @list_item, :edit?

    if @list_item.update(list_item_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(@list_item, partial: "list_items/item", locals: { item: @list_item, list: @list }),
            turbo_stream.replace("list-stats", partial: "shared/list_stats", locals: { list: @list })
          ]
        end
        format.json { render json: @list_item }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("list_item_#{@list_item.id}", partial: "list_items/item", locals: { item: @list_item, list: @list }),
          status: :unprocessable_entity
        end
        format.json { render json: @list_item.errors, status: :unprocessable_entity }
      end
    end
  end

  def show
    # Loads @list_item and @list via before_action
    authorize @list_item, :show?
  end

  def edit
    authorize @list_item, :edit?

    respond_to do |format|
      format.html  # For full page edit at /lists/:list_id/list_items/:id/edit
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("list_item_#{@list_item.id}",
                                                partial: "list_items/inline_edit_form",
                                                locals: { item: @list_item, list: @list })
      end
    end
  end

  # Redirect to the item's URL
  def visit_url
    authorize @list_item, :show?

    if valid_redirect_url?(@list_item.url)
      redirect_to @list_item.url, allow_other_host: true
    else
      redirect_to list_list_item_path(@list, @list_item), alert: "This item doesn't have a valid URL."
    end
  end

  # Display share/collaboration modal for list item
  def share
    authorize @list_item, :edit?

    @collaborators = @list_item.collaborators.includes(:user)
    @pending_invitations = @list_item.invitations.pending
    # Check if user can manage collaborators on this item
    @can_manage_collaborators = policy(@list_item).manage_collaborators?
    # Ensure @list is available for route generation
    @list ||= @list_item.list

    respond_to do |format|
      format.html do
        render :share, formats: [ :turbo_stream ], content_type: "text/vnd.turbo-stream.html"
      end
      format.turbo_stream
    end
  end

  # Toggle completion status using the new status enum
  def toggle_completion
    new_status = @list_item.status_completed? ? :pending : :completed
    new_column = if new_status == :completed
                   @list.board_columns.find_by(name: "Done")
    elsif new_status == :pending
                   @list.board_columns.find_by(name: "To Do")
    end

    if @list_item.update(status: new_status, board_column_id: new_column&.id)
      # Reload list associations to get fresh count data for stats
      @list.reload

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
            turbo_stream.replace(@list_item, partial: "list_items/item", locals: { item: @list_item, list: @list }),
            turbo_stream.replace("list-stats", partial: "shared/list_stats", locals: { list: @list })
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
        format.turbo_stream { render turbo_stream: turbo_stream.replace(@list_item, partial: "list_items/item", locals: { item: @list_item, list: @list }) }
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
          turbo_stream.replace("list-stats", partial: "shared/list_stats", locals: { list: @list })
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
          turbo_stream.replace("list-stats", partial: "shared/list_stats", locals: { list: @list }),
          items.map { |item| turbo_stream.replace(item, partial: "list_items/item", locals: { item: item, list: @list }) }
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
          turbo_stream.replace("list-stats", partial: "shared/list_stats", locals: { list: @list }),
          items.map { |item| turbo_stream.replace(item, partial: "list_items/item", locals: { item: item, list: @list }) }
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

  def valid_redirect_url?(url)
    return false if url.blank?

    # Allow http in development/test, https in production
    allowed_schemes = Rails.env.production? ? [ "https://" ] : [ "http://", "https://" ]
    return false unless allowed_schemes.any? { |scheme| url.start_with?(scheme) }

    # Validate URL structure
    begin
      URI.parse(url)
      true
    rescue URI::InvalidURIError
      false
    end
  end

  def list_item_params
    params.require(:list_item).permit(
      :title, :description, :item_type, :priority, :status,
      :due_date, :assigned_user_id, :url, :position,
      :estimated_duration, :duration_days, :start_date, :board_column_id
    )
  end
end
