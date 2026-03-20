module Connectors
  # Detect scheduling collisions across all user's calendar accounts
  class CollisionDetectorService < ApplicationService
    def initialize(user:, start_time:, end_time:, exclude_external_id: nil)
      @user = user
      @start_time = start_time
      @end_time = end_time
      @exclude_external_id = exclude_external_id
    end

    def call
      return failure(errors: [ "User is required" ]) unless @user

      collisions = []

      # Get all active calendar accounts for this user
      calendar_accounts = Connectors::Account.for_user(@user)
                                             .active_only
                                             .by_provider(%w[google_calendar microsoft_outlook])

      calendar_accounts.each do |account|
        account_collisions = detect_collisions_for_account(account)
        collisions.concat(account_collisions)
      end

      success(data: {
        collisions: collisions,
        has_conflicts: collisions.any?
      })
    rescue StandardError => e
      Rails.logger.error("Collision detection failed: #{e.message}")
      failure(errors: [ e.message ], message: "Failed to detect collisions")
    end

    private

    def detect_collisions_for_account(account)
      collisions = []

      # Set context for authorization
      Current.user = @user
      Current.organization = account.organization

      begin
        service = get_sync_service_for_account(account)
        calendar_id = account.settings.find_by(key: "default_calendar_id")&.value

        return [] unless calendar_id

        # Fetch events in the requested range
        events = service.send(:fetch_events_in_range, @start_time, @end_time, calendar_id)

        # Detect overlapping events
        events.each do |event|
          # Skip cancelled events
          next if event["status"] == "cancelled"

          # Skip all-day events
          next if is_all_day_event?(event)

          # Skip if this is the event we're excluding
          next if event["id"] == @exclude_external_id

          # Check for overlaps with other events in this account
          overlapping_events = find_overlapping_events(events, event)

          overlapping_events.each do |other_event|
            next if other_event["id"] == event["id"]
            next if other_event["id"] == @exclude_external_id
            next if is_all_day_event?(other_event)

            # Create collision record
            collision = build_collision_record(event, account, other_event)
            collisions << collision
          end
        end
      ensure
        Current.reset
      end

      collisions
    end

    def get_sync_service_for_account(account)
      case account.provider
      when "google_calendar"
        Google::EventSyncService.new(connector_account: account)
      when "microsoft_outlook"
        Microsoft::EventSyncService.new(connector_account: account)
      else
        raise "Unknown calendar provider: #{account.provider}"
      end
    end

    def is_all_day_event?(event)
      case event
      when Hash
        # Google format: has just "date" instead of "dateTime"
        event.dig("start", "date").present? || event.dig("start", "date").present?
      else
        false
      end
    end

    def find_overlapping_events(events, target_event)
      target_start = parse_datetime(target_event["start"])
      target_end = parse_datetime(target_event["end"])

      events.select do |event|
        event_start = parse_datetime(event["start"])
        event_end = parse_datetime(event["end"])

        # Check overlap: target_start < event_end AND target_end > event_start
        target_start < event_end && target_end > event_start
      end
    end

    def build_collision_record(event, account, other_event)
      {
        id: event["id"],
        title: event["summary"] || event["subject"],
        start: parse_datetime(event["start"]),
        end: parse_datetime(event["end"]),
        calendar: account.display_name,
        provider: account.provider,
        attendees: extract_attendee_emails(event, account.provider),
        organizer: extract_organizer_email(event, account.provider),
        overlapping_event_id: other_event["id"],
        overlapping_event_title: other_event["summary"] || other_event["subject"]
      }
    end

    def parse_datetime(time_obj)
      case time_obj
      when String
        Time.zone.parse(time_obj)
      when Hash
        if time_obj["dateTime"].present?
          Time.zone.parse(time_obj["dateTime"])
        elsif time_obj["date"].present?
          Time.zone.parse(time_obj["date"]).beginning_of_day
        end
      else
        Time.current
      end
    end

    def extract_attendee_emails(event, provider)
      case provider
      when "google_calendar"
        (event["attendees"] || []).map { |a| a["email"] }.compact
      when "microsoft_outlook"
        (event["attendees"] || []).map { |a| a.dig("emailAddress", "address") }.compact
      else
        []
      end
    end

    def extract_organizer_email(event, provider)
      case provider
      when "google_calendar"
        event.dig("organizer", "email")
      when "microsoft_outlook"
        event.dig("organizer", "emailAddress", "address")
      end
    end
  end
end
