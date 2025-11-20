class OrganizationsController < ApplicationController
  before_action :authenticate_user!

  # Show the organization switcher modal
  def switcher
    # Only allow turbo_stream requests - HTML requests should not directly access this
    unless request.format.turbo_stream?
      redirect_to dashboard_path, alert: "Invalid request"
      return
    end

    @organizations = current_user.organizations.where(status: :active).order(name: :asc)
    respond_to do |format|
      format.turbo_stream { render action: :switcher }
    end
  end

  # Switch to a different organization
  def switch
    @organization = Organization.find(params[:organization_id])
    authorize @organization, :show?

    # Only proceed if switching to a different organization
    if @organization.id == current_organization&.id
      respond_to do |format|
        format.turbo_stream { head :no_content }
        format.html { redirect_back(fallback_location: dashboard_path) }
      end
      return
    end

    # Set the new current organization in session
    self.current_organization = @organization

    # Set the new current organization for the user
    current_user.update(current_organization: @organization)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.refresh(request_id: "main")
      end
      format.html do
        redirect_back(fallback_location: dashboard_path, notice: "Switched to #{@organization.name}.")
      end
    end
  end
end
