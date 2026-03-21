class PeopleController < ApplicationController
  before_action :authenticate_user!

  def index
    @organization = Current.organization
    redirect_to root_path, alert: "Please select an organization first" unless @organization

    since = params[:since].present? ? params[:since].to_i.days.ago : 90.days.ago
    result = CollaborationGraphService.call(
      user: current_user,
      organization: @organization,
      since: since
    )

    @collaborators = result.success? ? result.data : []
    @since_days = params[:since].present? ? params[:since].to_i : 90
  end
end
