class CalendarEventsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_calendar_event

  def show
    authorize @calendar_event
  end

  private

  def set_calendar_event
    @calendar_event = CalendarEvent.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Calendar event not found."
  end
end
