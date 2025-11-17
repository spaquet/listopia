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

    # Always redirect, regardless of format
    redirect_to dashboard_path, notice: "Switched to #{org.name}."
  end
end
