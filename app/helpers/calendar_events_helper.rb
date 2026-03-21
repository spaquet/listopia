module CalendarEventsHelper
  def status_badge_classes(status)
    case status
    when "confirmed"
      "bg-green-100 text-green-800"
    when "tentative"
      "bg-yellow-100 text-yellow-800"
    when "cancelled"
      "bg-gray-100 text-gray-800"
    else
      "bg-gray-100 text-gray-800"
    end
  end

  def status_badge_label(status)
    case status
    when "confirmed"
      "Confirmed"
    when "tentative"
      "Tentative"
    when "cancelled"
      "Cancelled"
    else
      status.capitalize
    end
  end

  def provider_badge_classes(provider)
    case provider
    when "google_calendar"
      "bg-blue-100 text-blue-800"
    when "microsoft_outlook"
      "bg-cyan-100 text-cyan-800"
    else
      "bg-gray-100 text-gray-800"
    end
  end

  def provider_badge_label(provider)
    case provider
    when "google_calendar"
      "Google Calendar"
    when "microsoft_outlook"
      "Outlook"
    else
      provider.humanize
    end
  end

  def provider_badge_icon(provider)
    case provider
    when "google_calendar"
      "📅"
    when "microsoft_outlook"
      "📧"
    else
      "🔗"
    end
  end

  def external_calendar_link_label(provider)
    case provider
    when "google_calendar"
      "Open in Google Calendar"
    when "microsoft_outlook"
      "Open in Outlook"
    else
      "Open in Calendar"
    end
  end

  def attendee_response_classes(response)
    case response
    when "accepted"
      "text-green-700 font-semibold"
    when "declined"
      "text-red-700 font-semibold"
    when "tentativelyAccepted"
      "text-yellow-700 font-semibold"
    else
      "text-gray-700"
    end
  end

  def attendee_response_label(response)
    case response
    when "accepted"
      "Accepted"
    when "declined"
      "Declined"
    when "tentativelyAccepted"
      "Tentative"
    else
      response.humanize
    end
  end
end
