module Connectors
  module Google
    # Fetch Google Calendar list for authenticated user
    class CalendarFetchService < Connectors::BaseService
      GOOGLE_CALENDAR_API = "https://www.googleapis.com/calendar/v3"

      # Fetch list of calendars accessible to the user
      def fetch_calendars
        with_sync_log(operation: "fetch_calendars") do |log|
          ensure_fresh_token!

          calendars = fetch_from_google("/calendarList")

          log.update!(records_processed: calendars.count)

          calendars
        end
      end

      # Fetch a specific calendar by ID
      def fetch_calendar(calendar_id)
        with_sync_log(operation: "fetch_calendar") do |log|
          ensure_fresh_token!

          calendar = fetch_from_google("/calendars/#{calendar_id}")

          log.update!(records_processed: 1)

          calendar
        end
      end

      private

      def fetch_from_google(path)
        require "net/http"
        require "uri"

        url = "#{GOOGLE_CALENDAR_API}#{path}"
        uri = URI(url)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{connector_account.access_token}"

        response = http.request(request)

        raise "Google API error: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        data = JSON.parse(response.body)

        # Return items array or single item
        if data.key?("items")
          data["items"]
        else
          data
        end
      rescue StandardError => e
        Rails.logger.error("Google Calendar fetch failed: #{e.message}")
        raise
      end
    end
  end
end
