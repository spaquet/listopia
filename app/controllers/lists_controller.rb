# app/controllers/lists_controller.rb - Updated with proper context tracking
class ListsController < ApplicationController
  include ListBroadcasting

  before_action :authenticate_user!, except: [ :show, :show_by_slug ]
  before_action :set_list, only: [ :show, :kanban, :edit, :update, :destroy, :share, :toggle_public_access, :duplicate, :toggle_status, :ai_context ]
  before_action :authorize_list_access!, only: [ :show, :kanban, :edit, :update, :destroy, :share, :toggle_public_access, :duplicate, :ai_context ]

  # Display all lists accessible to the current user
  def index
    # Start with base scope from policy, filtered by current organization
    base_scope = if current_organization
      policy_scope(List).where(organization_id: current_organization.id)
    else
      policy_scope(List).where(organization_id: nil)
    end

    # Build the query step by step to avoid GROUP BY conflicts
    @lists = base_scope

    # Apply status filter (existing functionality)
    if params[:status].present?
      @lists = @lists.where(status: params[:status])
    end

    # Apply visibility filter (public/private)
    if params[:visibility].present?
      case params[:visibility]
      when "public"
        @lists = @lists.where(is_public: true)
      when "private"
        @lists = @lists.where(is_public: false)
      end
    end

    # Apply collaboration filter
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

    # Store current filters for the view
    @current_filters = {
      search: params[:search],
      status: params[:status],
      visibility: params[:visibility],
      collaboration: params[:collaboration]
    }

    respond_to do |format|
      format.html
      format.turbo_stream do
        render :index
      end
    end
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

  # Display list in kanban board view grouped by board columns
  def kanban
    authorize @list
    @board_columns = @list.board_columns.order(:position)
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
        format.turbo_stream {
          # Don't trigger additional broadcasts here since service already handled it
          render :create
        }
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
      # Add broadcasting for real-time updates to other users
      broadcast_all_updates(@list, action: :update)

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
    # Ensure only the owner can delete the list
    unless @list.owner == current_user
      respond_to do |format|
        format.html { redirect_to @list, alert: "Only the list owner can delete this list." }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "flash-messages",
            partial: "shared/flash_message",
            locals: { message: "Only the list owner can delete this list.", type: "alert" }
          )
        }
      end
      return
    end

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

  # NEW: AI Context endpoint for chat system
  def ai_context
    return head :unauthorized unless current_user

    context_data = {
      list: {
        id: @list.id,
        title: @list.title,
        status: @list.status,
        items_count: @list.list_items.count,
        completed_count: @list.list_items.status_completed.count,
        list_type: @list.list_type,
        is_public: @list.is_public?
      },
      items: @list.list_items.order(:position).limit(20).map do |item|
        {
          id: item.id,
          title: item.title,
          status: item.status,
          position: item.position,
          priority: item.priority,
          due_date: item.due_date,
          assigned_user_id: item.assigned_user_id
        }
      end,
      user_permissions: {
        can_edit: @list.writable_by?(current_user),
        can_collaborate: @list.collaboratable_by?(current_user),
        is_owner: @list.owner == current_user,
        can_manage_collaborators: policy(@list).manage_collaborators?
      },
      recent_activity: recent_list_activity
    }

    render json: context_data
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

  # NEW: Get user's role for the list
  def user_role_for_list(list)
    return "owner" if list.owner == current_user
    return "collaborator" if list.collaborators.exists?(user: current_user)
    return "public_viewer" if list.is_public?
    "unauthorized"
  end

  # NEW: Get recent activity for context
  def recent_list_activity
    return [] unless current_user

    current_user.conversation_contexts
      .where(entity_id: @list.id, entity_type: "List")
      .or(
        current_user.conversation_contexts
          .where("entity_data @> ?", { list_id: @list.id }.to_json)
      )
      .recent
      .limit(10)
      .map do |context|
        {
          action: context.action,
          created_at: context.created_at,
          entity_type: context.entity_type,
          relevance_score: context.relevance_score
        }
      end
  end

  # Strong parameters for list creation/updates
  def list_params
    params.require(:list).permit(:title, :description, :status, :is_public, :public_permission, :list_type, :color_theme)
  end
end
