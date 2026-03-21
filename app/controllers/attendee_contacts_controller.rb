class AttendeeContactsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_contact

  def show
    # Loads profile card via Turbo Frame
    @shared_meetings = CalendarEvent
      .where(user_id: current_user.id)
      .where("attendees @> ?", [{ email: @contact.email }].to_json)
      .order(start_time: :desc)
      .limit(10)
  end

  # PATCH /attendee_contacts/:id — manual enrichment update
  def update
    if @contact.update(contact_params)
      render turbo_stream: turbo_stream.replace(@contact)
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_contact
    @contact = AttendeeContact.find(params[:id])
    redirect_to root_path, alert: "Not found" unless @contact.organization_id == Current.organization&.id
  end

  def contact_params
    params.require(:attendee_contact).permit(
      :linkedin_url, :github_username, :twitter_url, :website_url,
      :title, :company, :location, :bio
    )
  end
end
