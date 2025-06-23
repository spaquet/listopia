# app/controllers/lists_controller.rb
class ListsController < ApplicationController
  before_action :authenticate_user!, except: [ :show ] # Allow public access to show if list is public
  before_action :set_list, only: [ :show, :edit, :update, :destroy ]
  before_action :authorize_list_access!, only: [ :show, :edit, :update, :destroy ]

  # Display all lists accessible to the current user
  def index
    @lists = current_user.accessible_lists.includes(:owner, :collaborators, :list_items)
                        .order(updated_at: :desc)
                        .page(params[:page])

    # Filter by status if provided
    @lists = @lists.where(status: params[:status]) if params[:status].present?

    # Search functionality
    if params[:search].present?
      @lists = @lists.where("title ILIKE ? OR description ILIKE ?",
                           "%#{params[:search]}%", "%#{params[:search]}%")
    end
  end

  # Display a specific list with its items
  def show
    @list_items = @list.list_items.includes(:assigned_user)
                      .order(:position, :created_at)

    @new_list_item = @list.list_items.build if @list.collaboratable_by?(current_user)

    # Track list views for analytics (optional)
    track_list_view if current_user
  end

  # Show form for creating a new list
  def new
    @list = current_user.lists.build
  end

  # Create a new list
  def create
    @list = current_user.lists.build(list_params)

    if @list.save
      respond_to do |format|
        format.html { redirect_to @list, notice: "List was successfully created." }
        format.turbo_stream { render :create }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.turbo_stream { render :form_errors }
      end
    end
  end

  # Show form for editing an existing list
  def edit
    # Form will be rendered
  end

  # Update an existing list
  def update
    if @list.update(list_params)
      respond_to do |format|
        format.html { redirect_to @list, notice: "List was successfully updated." }
        format.turbo_stream { render :update }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.turbo_stream { render :form_errors }
      end
    end
  end

  # Delete a list
  def destroy
    @list.destroy

    respond_to do |format|
      format.html { redirect_to lists_path, notice: "List was successfully deleted." }
      format.turbo_stream { render :destroy }
    end
  end

  # Toggle list completion status
  def toggle_status
    @list = current_user.accessible_lists.find(params[:id])
    authorize_resource_access!(@list, :edit)

    new_status = @list.status_completed? ? :active : :completed
    @list.update!(status: new_status)

    respond_with_turbo_stream do
      render :toggle_status
    end
  end

  private

  # Find list by ID, handling public access for public lists
  def set_list
    if current_user
      @list = current_user.accessible_lists.find(params[:id])
    else
      # Allow access to public lists for non-authenticated users
      @list = List.find(params[:id])
      redirect_to root_path, alert: "List not found." unless @list.is_public?
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to lists_path, alert: "List not found."
  end

  # Check if user has permission to access the list
  def authorize_list_access!
    action = case action_name
    when "show" then :read
    when "edit", "update", "destroy", "toggle_status" then :edit
    else :read
    end

    authorize_resource_access!(@list, action)
  end

  # Strong parameters for list creation/update
  def list_params
    params.require(:list).permit(:title, :description, :status, :is_public, :color_theme, metadata: {})
  end

  # Track list views for analytics (implement as needed)
  def track_list_view
    # Could track in Redis, database, or analytics service
    Rails.logger.info "User #{current_user.id} viewed list #{@list.id}"
  end
end
