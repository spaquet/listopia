# app/controllers/admin/organizations_controller.rb
class Admin::OrganizationsController < Admin::BaseController
  before_action :set_organization, only: %i[show edit update destroy suspend reactivate audit_logs members]

  def index
    authorize Organization

    # Get only organizations where user is owner or admin
    user_manageable_orgs = Organization.joins(:organization_memberships)
                                        .where(
                                          organization_memberships: {
                                            user_id: current_user.id,
                                            role: [ :owner, :admin ]
                                          }
                                        )
                                        .distinct

    # Apply filters to user's manageable organizations
    @filter_service = OrganizationFilterService.new(
      query: params[:query],
      status: params[:status],
      size: params[:size],
      sort_by: params[:sort_by],
      base_scope: user_manageable_orgs
    )

    @organizations = @filter_service.filtered_organizations.includes(:creator).limit(100)

    @filters = {
      query: @filter_service.query,
      status: @filter_service.status,
      size: @filter_service.size,
      sort_by: @filter_service.sort_by
    }

    # Count only user's manageable organizations
    @total_organizations = user_manageable_orgs.count

    respond_to do |format|
      format.html
      format.turbo_stream do
        render :index
      end
    end
  rescue => e
    Rails.logger.error("Organization filter error: #{e.message}\n#{e.backtrace.join("\n")}")
    flash.now[:alert] = "An error occurred while filtering organizations"
    render :index, status: :unprocessable_entity
  end

  def show
    authorize @organization, :show?
  end

  def new
    @organization = Organization.new
    authorize @organization, :create?
    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def create
    @organization = Organization.new(organization_params)
    @organization.created_by_id = current_user.id
    authorize @organization, :create?

    if @organization.save
      # Add creator as owner
      @organization.organization_memberships.create!(
        user: current_user,
        role: :owner,
        status: :active
      )

      respond_to do |format|
        format.html { redirect_to admin_organization_path(@organization), notice: "Organization created successfully." }
        format.turbo_stream { render :create }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.turbo_stream { render :new }
      end
    end
  end

  def edit
    authorize @organization, :update?
  end

  def update
    authorize @organization, :update?

    if @organization.update(organization_params)
      redirect_to admin_organization_path(@organization), notice: "Organization updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @organization, :destroy?

    if @organization.destroy
      redirect_to admin_organizations_path, notice: "Organization deleted successfully."
    else
      redirect_to admin_organization_path(@organization), alert: "Unable to delete organization."
    end
  end

  def members
    authorize @organization, :manage_members?
    @pagy, @members = pagy(@organization.organization_memberships.includes(:user).order(created_at: :desc))
  end

  def suspend
    authorize @organization, :suspend?

    if @organization.suspend!
      message = "Organization suspended successfully."
    else
      message = "Failed to suspend organization."
    end

    respond_to do |format|
      format.html { redirect_to admin_organizations_path, notice: message }
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("organization_#{@organization.id}",
            partial: "organization_row", locals: { organization: @organization }),
          turbo_stream.update("active-organizations-count", Organization.where(status: :active).count),
          turbo_stream.update("suspended-count", Organization.where(status: :suspended).count)
        ]
      end
    end
  end

  def reactivate
    authorize @organization, :reactivate?

    if @organization.reactivate!
      message = "Organization reactivated successfully."
    else
      message = "Failed to reactivate organization."
    end

    respond_to do |format|
      format.html { redirect_to admin_organizations_path, notice: message }
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("organization_#{@organization.id}",
            partial: "organization_row", locals: { organization: @organization }),
          turbo_stream.update("active-organizations-count", Organization.where(status: :active).count),
          turbo_stream.update("suspended-count", Organization.where(status: :suspended).count)
        ]
      end
    end
  end

  def audit_logs
    authorize @organization, :audit_logs?
    @audits = @organization.audits.order(created_at: :desc).limit(50)
  end

  private

  def set_organization
    @organization = Organization.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_organizations_path, alert: "Organization not found."
  end

  def organization_params
    params.require(:organization).permit(:name, :size)
  end
end
