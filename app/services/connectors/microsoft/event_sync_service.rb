module Connectors
  module Microsoft
    # Sync events between Outlook and Listopia via Microsoft Graph API
    class EventSyncService < Connectors::SyncService
      GRAPH_API = "https://graph.microsoft.com/v1.0"

      # Pull events from Outlook Calendar
      def pull_events
        with_sync_log(operation: "pull_events") do |log|
          ensure_fresh_token!

          calendar_id = connector_account.settings.find_by(key: "default_calendar_id")&.value
          return { count: 0, events: [] } unless calendar_id

          events = fetch_outlook_events(calendar_id)

          created = 0
          updated = 0

          events.each do |event|
            mapping = find_or_create_mapping(event, calendar_id)
            created += 1 if mapping.created_at == mapping.updated_at
            updated += 1 unless mapping.created_at == mapping.updated_at
          end

          log.update!(
            records_processed: events.count,
            records_created: created,
            records_updated: updated
          )

          { count: events.count, events: events }
        end
      end

      # Push events to Outlook Calendar
      def push_events(items)
        with_sync_log(operation: "push_events") do |log|
          ensure_fresh_token!

          calendar_id = connector_account.settings.find_by(key: "default_calendar_id")&.value
          return { count: 0, events: [] } unless calendar_id

          created = 0
          updated = 0

          items.each do |item|
            event_data = build_event_data(item)
            result = push_to_outlook(event_data, calendar_id)

            if result[:created]
              created += 1
              map_event(
                external_id: result[:id],
                external_type: "outlook_event",
                local_type: "ListItem",
                local_id: item[:id]
              )
            else
              updated += 1
            end
          end

          log.update!(
            records_processed: items.count,
            records_created: created,
            records_updated: updated
          )

          { count: items.count, events: items }
        end
      end

      private

      def fetch_outlook_events(calendar_id)
        require "net/http"
        require "uri"

        # Build query for events in date range
        now = Time.current
        start_time = 30.days.ago
        end_time = 30.days.from_now

        url = "#{GRAPH_API}/me/calendars/#{calendar_id}/calendarview"
        uri = URI(url)
        uri.query = URI.encode_www_form(
          startDateTime: start_time.iso8601,
          endDateTime: end_time.iso8601
        )

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{connector_account.access_token}"

        response = http.request(request)

        raise "Failed to fetch events" unless response.is_a?(Net::HTTPSuccess)

        data = JSON.parse(response.body)
        data["value"] || []
      rescue StandardError => e
        Rails.logger.error("Failed to fetch Outlook events: #{e.message}")
        []
      end

      def fetch_events_in_range(start_time, end_time, calendar_id)
        require "net/http"
        require "uri"

        url = "#{GRAPH_API}/me/calendars/#{calendar_id}/calendarview"
        uri = URI(url)
        uri.query = URI.encode_www_form(
          startDateTime: start_time.iso8601,
          endDateTime: end_time.iso8601
        )

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{connector_account.access_token}"

        response = http.request(request)

        raise "Failed to fetch events" unless response.is_a?(Net::HTTPSuccess)

        data = JSON.parse(response.body)
        data["value"] || []
      rescue StandardError => e
        Rails.logger.error("Failed to fetch Outlook events in range: #{e.message}")
        []
      end

      def push_to_outlook(event_data, calendar_id)
        require "net/http"
        require "uri"

        url = "#{GRAPH_API}/me/calendars/#{calendar_id}/events"
        uri = URI(url)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{connector_account.access_token}"
        request["Content-Type"] = "application/json"
        request.body = event_data.to_json

        response = http.request(request)

        raise "Failed to push event" unless response.is_a?(Net::HTTPSuccess)

        data = JSON.parse(response.body)

        { id: data["id"], created: true }
      rescue StandardError => e
        Rails.logger.error("Failed to push event to Outlook: #{e.message}")
        { id: nil, created: false }
      end

      def build_event_data(item)
        {
          subject: item[:title] || "Untitled",
          bodyPreview: item[:description],
          start: {
            dateTime: (item[:start_time] || Time.current).iso8601,
            timeZone: "UTC"
          },
          end: {
            dateTime: (item[:end_time] || 1.hour.from_now).iso8601,
            timeZone: "UTC"
          }
        }
      end

      def find_or_create_mapping(event, calendar_id)
        map_event(
          external_id: event["id"],
          external_type: "outlook_event",
          local_type: "ListItem",
          local_id: nil,
          metadata: {
            calendar_id: calendar_id,
            change_key: event["changeKey"],
            updated_at: event["lastModifiedDateTime"]
          }
        )
      end
    end
  end
end
