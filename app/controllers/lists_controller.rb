# app/controllers/lists_controller.rb
class ListsController < ApplicationController
  before_action :authenticate_user!, except: [ :show, :show_by_slug ] # Allow public access to show methods
  before_action :set_list, only: [ :show, :edit, :update, :destroy, :share, :toggle_public_access, :duplicate ]
before_action :authorize_list_access!, only: [ :show, :edit, :update, :destroy, :share, :toggle_public_access, :duplicate ]
  # Display all lists accessible to the current user
  def index
    @lists = current_user.accessible_lists.includes(:owner, :collaborators, :list_items)
                        .order(updated_at: :desc)

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

    @new_list_item = @list.list_items.build if can_collaborate_on_list?

    # Track list views for analytics (optional)
    track_list_view if current_user
  end

  # Show public list by slug (prettier URLs for sharing)
  def show_by_slug
    @list = List.find_by!(public_slug: params[:slug], is_public: true)
    @list_items = @list.list_items.includes(:assigned_user)
                      .order(:position, :created_at)

    @new_list_item = @list.list_items.build if can_collaborate_on_list?

    # Track list views for analytics (optional)
    track_list_view if current_user

    # Render the same template as regular show
    render :show
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "List not found or not publicly available."
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
        format.turbo_stream do
          # For successful creation, always redirect to the new list
          redirect_to @list, notice: "List was successfully created."
        end
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.turbo_stream do
          # Only use Turbo Stream for validation errors
          flash.now[:alert] = "Please fix the errors below."
          render :new, status: :unprocessable_entity
        end
      end
    end
  end

  # Show form for editing an existing list
  def edit
    # Form will be rendered
  end

  # Show sharing modal/page
  def share
    @sharing_service = ListSharingService.new(@list, current_user)
    @sharing_summary = @sharing_service.sharing_summary

    respond_to do |format|
      format.html # Will render share.html.erb
      format.turbo_stream # For modal rendering
    end
  end

  # Update an existing list
  def update
    # Store previous status for notifications
    previous_status = @list.status

    if @list.update(list_params)
      respond_to do |format|
        format.html { redirect_to @list, notice: "List was successfully updated." }
        format.turbo_stream do
          # For successful updates, redirect to the list instead of trying to replace elements
          redirect_to @list, notice: "List was successfully updated."
        end
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.turbo_stream do
          # For validation errors, re-render the edit form
          flash.now[:alert] = "Please fix the errors below."
          render :edit, status: :unprocessable_entity
        end
      end
    end
  end

  # Delete a list
  def destroy
    @list.destroy

    respond_to do |format|
      format.html { redirect_to lists_path, notice: "List was successfully deleted." }
      format.turbo_stream do
        # Always redirect to lists index after deletion
        redirect_to lists_path, notice: "List was successfully deleted."
      end
    end
  end

  # Toggle list completion status
  def toggle_status
    @list = current_user.accessible_lists.find(params[:id])
    authorize_resource_access!(@list, :edit)

    previous_status = @list.status
    new_status = @list.status_completed? ? :active : :completed
    @list.update!(status: new_status)

    respond_with_turbo_stream do
      render :toggle_status
    end
  end

  # Toggle public access for the list
  def toggle_public_access
    authorize_resource_access!(@list, :edit)

    if @list.is_public?
      # Make private
      @list.update!(is_public: false)
    else
      # Make public and generate slug if needed
      @list.update!(
        is_public: true,
        public_slug: @list.public_slug.presence || SecureRandom.urlsafe_base64(8)
      )
    end

    # Return updated sharing data
    @sharing_service = ListSharingService.new(@list, current_user)
    @sharing_summary = @sharing_service.sharing_summary

    respond_to do |format|
      format.turbo_stream { render :toggle_public_access }
      format.json { render json: @sharing_summary }
    end
  end

  # Duplicate a list and its items
  def duplicate
    authorize_resource_access!(@list, :read) # Only need read access to duplicate

    # Create a new list with similar attributes
    new_list = current_user.lists.build(
      title: "Copy of #{@list.title}",
      description: @list.description,
      color_theme: @list.color_theme,
      status: :draft, # Always start as draft
      metadata: @list.metadata&.deep_dup
    )

    if new_list.save
      # Duplicate all list items
      @list.list_items.find_each do |item|
        new_list.list_items.create!(
          title: item.title,
          description: item.description,
          item_type: item.item_type,
          priority: item.priority,
          url: item.url,
          due_date: item.due_date, # Keep due dates as-is
          position: item.position,
          metadata: item.metadata&.deep_dup,
          completed: false, # Reset completion status
          completed_at: nil
          # Note: assigned_user_id is intentionally omitted to reset assignments
        )
      end

      # Simple redirect to the new list
      redirect_to new_list
    else
      # If duplication fails, redirect back to original list
      redirect_to @list, alert: "Failed to duplicate list. Please try again."
    end
  rescue => e
    Rails.logger.error "List duplication failed: #{e.message}"
    redirect_to @list, alert: "Failed to duplicate list. Please try again."
  end

  private

  # Find list by ID, handling public access for public lists
  def set_list
    if current_user
      # Authenticated user - use accessible lists
      @list = current_user.accessible_lists.find(params[:id])
    else
      # Non-authenticated user - only allow access to public lists
      @list = List.find(params[:id])
      unless @list.is_public?
        redirect_to new_session_path, alert: "Please sign in to access this list."
        nil
      end
    end
  rescue ActiveRecord::RecordNotFound
    if current_user
      redirect_to lists_path, alert: "List not found."
    else
      redirect_to root_path, alert: "List not found."
    end
  end

  # Check if user has permission to access the list
  def authorize_list_access!
    action = case action_name
    when "show" then :read
    when "edit", "update", "destroy", "toggle_status" then :edit
    else :read
    end

    # For public lists, allow read access even without authentication
    if action == :read && @list.is_public?
      return true
    end

    # For all other cases, use the standard authorization
    authorize_resource_access!(@list, action)
  end

  # Check if current user can collaborate on this list
  def can_collaborate_on_list?
    return false unless current_user
    @list.collaboratable_by?(current_user)
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
