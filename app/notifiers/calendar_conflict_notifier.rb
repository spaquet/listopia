class CalendarConflictNotifier < ApplicationNotifier
  def notification_type
    "calendar_conflict"
  end

  def title
    "Calendar conflict detected"
  end

  def message
    count = params[:conflict_count]
    summary = params[:first_conflict_summary]
    count == 1 ? "Schedule conflict: \"#{summary}\" overlaps with another event" :
                 "#{count} calendar conflicts detected — including \"#{summary}\""
  end

  def url
    Rails.application.routes.url_helpers.connectors_calendars_conflicts_path
  end

  def icon
    "calendar_x"
  end
end
