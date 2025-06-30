# app/controllers/lists_controller.rb
class ListsController < ApplicationController
  include ListBroadcasting

  before_action :authenticate_user!, except: [ :show, :show_by_slug ]
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
      # Broadcast updates to other users after successful creation
      broadcast_all_updates(@list)

      respond_to do |format|
        format.html { redirect_to @list, notice: "List was successfully created." }
        format.turbo_stream do
          # Use turbo streams to update multiple parts of the page
          render :create
        end
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.turbo_stream do
          flash.now[:alert] = "Please fix the errors below."
          render :new, status: :unprocessable_entity
        end
      end
    end
  end

  # Check if user has permission to access the list
  def authorize_list_access!
    action = case action_name
    when "show" then :read
    when "edit", "update", "destroy", "toggle_status", "toggle_public_access" then :edit
    else :read
    end

    # For public lists, allow read access even without authentication
    if action == :read && @list.is_public?
      return true
    end

    # For all other cases, use the standard authorization
    authorize_resource_access!(@list, action)
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
      # Broadcast updates to other users after successful update
      broadcast_all_updates(@list)

      respond_to do |format|
        format.html { redirect_to @list, notice: "List was successfully updated." }
        format.turbo_stream do
          # Use turbo streams to update multiple parts of the page
          render :update
        end
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.turbo_stream do
          flash.now[:alert] = "Please fix the errors below."
          render :edit, status: :unprocessable_entity
        end
      end
    end
  end

  # Delete a list
  def destroy
    # Store list data before destruction for broadcasting
    list_for_broadcast = @list.dup
    list_for_broadcast.owner = @list.owner
    list_for_broadcast.collaborators = @list.collaborators.to_a

    @list.destroy

    # Broadcast updates to other users after successful deletion
    broadcast_all_updates(list_for_broadcast)

    respond_to do |format|
      format.html { redirect_to lists_path, notice: "List was successfully deleted." }
      format.turbo_stream do
        # Use turbo streams to update multiple parts of the page
        render :destroy
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

    # Broadcast updates to other users after successful status change
    broadcast_all_updates(@list)

    respond_to do |format|
      format.turbo_stream do
        render :toggle_status
      end
      format.html { redirect_to @list, notice: "List status updated successfully!" }
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
      @list.update!(is_public: true)
      @list.generate_public_slug! if @list.public_slug.blank?
    end

    # Broadcast updates to other users after successful public access change
    broadcast_all_updates(@list)

    respond_to do |format|
      format.turbo_stream do
        render :toggle_public_access
      end
      format.html { redirect_to @list, notice: "List visibility updated successfully!" }
    end
  end

  # Duplicate a list
  def duplicate
    authorize_resource_access!(@list, :read)

    @new_list = @list.duplicate_for_user(current_user)

    if @new_list.persisted?
      # Broadcast updates to other users after successful duplication
      broadcast_all_updates(@new_list)

      respond_to do |format|
        format.html { redirect_to @new_list, notice: "List was successfully duplicated." }
        format.turbo_stream do
          # Use turbo streams to update multiple parts of the page
          @list = @new_list # Set @list to the new list for the turbo stream template
          render :create # Use the same template as create
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to @list, alert: "Could not duplicate list." }
        format.turbo_stream do
          flash.now[:alert] = "Could not duplicate list."
          render :error
        end
      end
    end
  end

  private

  # Find the list ensuring user has access
  def set_list
    @list = current_user.accessible_lists.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to lists_path, alert: "List not found."
  end

  # Check if user can collaborate on this list
  def can_collaborate_on_list?
    current_user && can_access_list?(@list, current_user, :edit)
  end

  # Track list views for analytics
  def track_list_view
    # Implementation for analytics tracking
    # Could store in a separate analytics table
  end

  def can_access_list?(list, user, permission = :read)
    return false unless user && list

    case permission
    when :read
      list.readable_by?(user)
    when :edit
      list.collaboratable_by?(user)
    else
      false
    end
  end

  # Strong parameters for list creation/updates
  def list_params
    params.require(:list).permit(:title, :description, :status, :is_public, :list_type, :color_theme)
  end
end
