# app/controllers/lists_controller.rb
class ListsController < ApplicationController
  include ListBroadcasting

  before_action :authenticate_user!, except: [ :show, :show_by_slug ]
  before_action :set_list, only: [ :show, :edit, :update, :destroy, :share, :toggle_public_access, :duplicate, :toggle_status ]
  before_action :authorize_list_access!, only: [ :show, :edit, :update, :destroy, :share, :toggle_public_access, :duplicate ]

  # Display all lists accessible to the current user
  def index
    # Start with base scope from policy
    base_scope = policy_scope(List)

    # Build the query step by step to avoid GROUP BY conflicts
    @lists = base_scope

    # Apply status filter (existing functionality)
    if params[:status].present?
      @lists = @lists.where(status: params[:status])
    end

    # NEW: Apply visibility filter (public/private)
    if params[:visibility].present?
      case params[:visibility]
      when "public"
        @lists = @lists.where(is_public: true)
      when "private"
        @lists = @lists.where(is_public: false)
      end
    end

    # NEW: Apply collaboration filter
    if params[:collaboration].present?
      case params[:collaboration]
      when "owned"
        # Only lists owned by current user
        @lists = @lists.where(user_id: current_user.id)
      when "shared_with_me"
        # Only lists where current user is a collaborator (not owner)
        # Use subquery to avoid GROUP BY issues
        collaborated_list_ids = Collaborator.where(
          collaboratable_type: "List",
          user_id: current_user.id
        ).pluck(:collaboratable_id)

        @lists = @lists.where(id: collaborated_list_ids)
                      .where.not(user_id: current_user.id)
      when "shared_by_me"
        # Only lists owned by current user that have collaborators
        # Use subquery to find lists with collaborators
        lists_with_collaborators = Collaborator.where(
          collaboratable_type: "List"
        ).select(:collaboratable_id).distinct

        @lists = @lists.where(user_id: current_user.id)
                      .where(id: lists_with_collaborators)
      end
    end

    # Apply search filter (enhanced version)
    if params[:search].present?
      search_term = "%#{params[:search].strip}%"
      @lists = @lists.where(
        "title ILIKE ? OR description ILIKE ?",
        search_term, search_term
      )
    end

    # Apply includes and ordering at the end
    @lists = @lists.includes(:owner, :collaborators)
                  .order(updated_at: :desc)
  end

  # Display a specific list with its items
  def show
    authorize @list

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
    authorize @list

    respond_to do |format|
      format.html # Regular page (lists/new.html.erb)
      format.turbo_stream # Modal (lists/new.turbo_stream.erb)
    end
  end

  # Create a new list
  def create
    @list = current_user.lists.build(list_params)
    authorize @list

    service = ListCreationService.new(current_user)
    result = service.create_list(**list_params.to_h.symbolize_keys)

    if result.success?
      @list = result.data
      respond_to do |format|
        format.html { redirect_to lists_path, notice: "List was successfully created." }
        format.turbo_stream { render :create }
      end
    else
      @list = service.list # Get the unsaved list with errors for form redisplay
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.turbo_stream do
          flash.now[:alert] = result.errors.join(", ")
          render :new, status: :unprocessable_entity
        end
      end
    end
  end

  # Show form for editing a list
  def edit
    authorize @list
  end

  # Update an existing list
  def update
    authorize @list

    if @list.update(list_params)
      respond_to do |format|
        format.html { redirect_to @list, notice: "List was successfully updated." }
        format.turbo_stream { render :update }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.turbo_stream { render :edit_errors }
      end
    end
  end

  # Delete a list
  def destroy
    authorize @list

    @list.destroy
    respond_to do |format|
      format.html { redirect_to lists_path, notice: "List was successfully deleted." }
      format.turbo_stream { render :destroy }
    end
  end

  # Toggle list status (draft -> active -> completed -> archived)
  def toggle_status
    authorize @list, :update?

    service = ListManagementService.new(@list, current_user)
    result = service.toggle_status

    if result.success?
      respond_to do |format|
        format.html { redirect_to @list, notice: "List status updated to #{@list.status.humanize}" }
        format.turbo_stream { render :status_updated }
      end
    else
      respond_to do |format|
        format.html { redirect_to @list, alert: result.errors.join(", ") }
        format.turbo_stream { render :status_error }
      end
    end
  end

  # Toggle public access for a list
  def toggle_public_access
    authorize @list, :update?

    @list.update!(is_public: !@list.is_public?)

    # Generate public slug if making public
    if @list.is_public? && @list.public_slug.blank?
      @list.update!(public_slug: SecureRandom.urlsafe_base64(8))
    end

    respond_to do |format|
      format.html { redirect_to @list, notice: "Public access #{@list.is_public? ? 'enabled' : 'disabled'}" }
      format.turbo_stream { render :public_access_toggled }
    end
  end

  # Duplicate a list
  def duplicate
    authorize @list, :show?

    service = ListDuplicationService.new(@list, current_user)
    result = service.duplicate

    if result.success?
      @new_list = result.data
      respond_to do |format|
        format.html { redirect_to @new_list, notice: "List duplicated successfully!" }
        format.turbo_stream { render :duplicated }
      end
    else
      respond_to do |format|
        format.html { redirect_to @list, alert: result.errors.join(", ") }
        format.turbo_stream { render :duplication_error }
      end
    end
  end

  # Show sharing options for a list
  def share
    authorize @list, :manage_collaborators?

    @collaborators = @list.collaborators.includes(:user)
    @invitations = @list.invitations.pending.includes(:invited_by)
    @sharing_service = ListSharingService.new(@list, current_user)
    @sharing_summary = @sharing_service.sharing_summary
  end

  private

  def set_list
    @list = List.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to lists_path, alert: "List not found."
  end

  # Check if user has permission to access the list using Pundit
  def authorize_list_access!
    authorize @list
  end

  # Check if user can collaborate on this list
  def can_collaborate_on_list?
    current_user && policy(@list).update?
  end

  # Track list views for analytics
  def track_list_view
    # Implementation for analytics tracking
    # Could store in a separate analytics table
    # ListAnalyticsService.new(@list, current_user).track_view
    @list.touch if @list && current_user
  end

  # Strong parameters for list creation/updates
  def list_params
    params.require(:list).permit(:title, :description, :status, :is_public, :public_permission, :list_type, :color_theme)
  end
end
