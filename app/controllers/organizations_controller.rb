class OrganizationsController < ApplicationController
  before_action :authenticate_user!

  def switcher
    respond_to do |format|
      format.html { render :switcher }
    end
  end

  def switch
    org = Organization.find(params[:organization_id])
    authorize org, :show?

    self.current_organization = org

    respond_to do |format|
      format.html { redirect_to dashboard_path, notice: "Switched to #{org.name}." }
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove("org_switcher_modal"),
          turbo_stream.action(:redirect, to: dashboard_path)
        ]
      end
    end
  end
end
