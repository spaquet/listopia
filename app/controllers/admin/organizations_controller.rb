# app/controllers/admin/organizations_controller.rb
class Admin::OrganizationsController < Admin::BaseController
  before_action :set_organization, only: %i[show suspend reactivate audit_logs]

  def index
    authorize Organization

    # Apply filters
    @filter_service = OrganizationFilterService.new(
      query: params[:query],
      status: params[:status],
      size: params[:size],
      sort_by: params[:sort_by]
    )

    @organizations = @filter_service.filtered_organizations.includes(:creator).limit(100)

    @filters = {
      query: @filter_service.query,
      status: @filter_service.status,
      size: @filter_service.size,
      sort_by: @filter_service.sort_by
    }

    @total_organizations = Organization.count

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
        render turbo_stream: turbo_stream.replace("organization_#{@organization.id}",
          partial: "organization_row", locals: { organization: @organization })
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
        render turbo_stream: turbo_stream.replace("organization_#{@organization.id}",
          partial: "organization_row", locals: { organization: @organization })
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
end
