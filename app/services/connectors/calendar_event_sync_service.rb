module Connectors
  # Sync calendar events from external calendar providers into CalendarEvent model
  class CalendarEventSyncService < Connectors::BaseService
    # Sync events from connector account into local CalendarEvent records
    # Fetches 90 days back to 30 days forward
    def call
      with_sync_log(operation: "calendar_event_sync") do |log|
        ensure_fresh_token!

        calendar_id = connector_account.settings.find_by(key: "default_calendar_id")&.value
        return success(data: { synced: 0 }) unless calendar_id

        start_time = 90.days.ago
        end_time = 30.days.from_now

        events = fetch_events_from_provider(calendar_id, start_time, end_time)

        synced_count = 0
        events.each do |event|
          next if event["status"] == "cancelled"

          upsert_calendar_event(event, calendar_id)
          synced_count += 1
        end

        log.update!(
          records_processed: events.count,
          records_created: synced_count
        )

        # Trigger async conflict detection after sync completes
        DetectCalendarConflictsJob.perform_later(
          user_id: connector_account.user_id,
          organization_id: connector_account.organization_id
        )

        success(data: { synced: synced_count })
      end
    end

    private

    def fetch_events_from_provider(calendar_id, start_time, end_time)
      service = get_sync_service
      service.send(:fetch_events_in_range, start_time, end_time, calendar_id)
    end

    def get_sync_service
      case connector_account.provider
      when "google_calendar"
        Google::EventSyncService.new(connector_account: connector_account)
      when "microsoft_outlook"
        Microsoft::EventSyncService.new(connector_account: connector_account)
      else
        raise "Unknown calendar provider: #{connector_account.provider}"
      end
    end

    def upsert_calendar_event(event, calendar_id)
      external_event_id = event["id"]
      provider = connector_account.provider

      # Build event data from provider response
      start_dt = parse_datetime(event["start"])
      end_dt = parse_datetime(event["end"])

      # Find or initialize calendar event
      cal_event = CalendarEvent.find_or_initialize_by(
        external_event_id: external_event_id
      )

      cal_event.assign_attributes(
        user_id: connector_account.user_id,
        organization_id: connector_account.organization_id,
        connector_account_id: connector_account.id,
        provider: provider,
        summary: event["summary"] || event["subject"],
        description: event["description"] || event["bodyPreview"],
        start_time: start_dt,
        end_time: end_dt,
        status: normalize_status(event["status"]),
        timezone: extract_timezone(event),
        organizer_email: extract_organizer_email(event),
        organizer_name: extract_organizer_name(event),
        is_organizer: check_is_organizer(event),
        attendees: extract_attendees(event),
        external_event_url: extract_external_event_url(event)
      )

      # Mark for embedding update if new or content changed
      cal_event.requires_embedding_update = true if cal_event.new_record? || cal_event.summary_changed? || cal_event.description_changed?

      cal_event.save!

      # Sync attendees to AttendeeContact records for collaboration graph
      organization = Organization.find(connector_account.organization_id)
      AttendeeContactSyncService.new(
        calendar_event: cal_event,
        organization: organization
      ).call

      cal_event
    end

    def parse_datetime(time_obj)
      case time_obj
      when String
        Time.zone.parse(time_obj)
      when Hash
        # Google format: { dateTime: "2023-01-01T10:00:00Z" } or { date: "2023-01-01" }
        if time_obj["dateTime"].present?
          Time.zone.parse(time_obj["dateTime"])
        elsif time_obj["date"].present?
          Time.zone.parse(time_obj["date"]).beginning_of_day
        end
      else
        Time.current
      end
    end

    def extract_timezone(event)
      case connector_account.provider
      when "google_calendar"
        event.dig("start", "timeZone") || "UTC"
      when "microsoft_outlook"
        event.dig("start", "timeZone") || "UTC"
      else
        "UTC"
      end
    end

    def normalize_status(status)
      case status
      when "tentativelyAccepted", "tentative"
        "tentative"
      when "declined", "cancelled"
        "cancelled"
      else
        "confirmed"
      end
    end

    def extract_organizer_email(event)
      case connector_account.provider
      when "google_calendar"
        event.dig("organizer", "email")
      when "microsoft_outlook"
        event.dig("organizer", "emailAddress", "address")
      end
    end

    def extract_organizer_name(event)
      case connector_account.provider
      when "google_calendar"
        event.dig("organizer", "displayName")
      when "microsoft_outlook"
        event.dig("organizer", "emailAddress", "name")
      end
    end

    def check_is_organizer(event)
      case connector_account.provider
      when "google_calendar"
        organizer_email = extract_organizer_email(event)
        connector_account.email == organizer_email
      when "microsoft_outlook"
        organizer_email = extract_organizer_email(event)
        connector_account.email == organizer_email
      else
        false
      end
    end

    def extract_attendees(event)
      attendees = []

      case connector_account.provider
      when "google_calendar"
        if event["attendees"].is_a?(Array)
          attendees = event["attendees"].map do |attendee|
            {
              email: attendee["email"],
              displayName: attendee["displayName"],
              responseStatus: attendee["responseStatus"]
            }
          end
        end
      when "microsoft_outlook"
        if event["attendees"].is_a?(Array)
          attendees = event["attendees"].map do |attendee|
            {
              email: attendee.dig("emailAddress", "address"),
              displayName: attendee.dig("emailAddress", "name"),
              responseStatus: attendee["status"]&.dig("response")
            }
          end
        end
      end

      attendees.compact
    end

    def extract_external_event_url(event)
      case connector_account.provider
      when "google_calendar"
        event["htmlLink"]
      when "microsoft_outlook"
        event["webLink"]
      end
    end
  end
end
