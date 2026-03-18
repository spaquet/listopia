module Connectors
  module Microsoft
    # Fetch Outlook calendars via Microsoft Graph API
    class CalendarFetchService < Connectors::BaseService
      GRAPH_API = "https://graph.microsoft.com/v1.0"

      # Fetch list of calendars accessible to the user
      def fetch_calendars
        with_sync_log(operation: "fetch_calendars") do |log|
          ensure_fresh_token!

          calendars = fetch_from_graph("/me/calendars")

          log.update!(records_processed: calendars.count)

          calendars
        end
      end

      # Fetch a specific calendar by ID
      def fetch_calendar(calendar_id)
        with_sync_log(operation: "fetch_calendar") do |log|
          ensure_fresh_token!

          calendar = fetch_from_graph("/me/calendars/#{calendar_id}")

          log.update!(records_processed: 1)

          calendar
        end
      end

      private

      def fetch_from_graph(path)
        require "net/http"
        require "uri"

        url = "#{GRAPH_API}#{path}"
        uri = URI(url)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{connector_account.access_token}"

        response = http.request(request)

        raise "Microsoft Graph error: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        data = JSON.parse(response.body)

        # Return items array or single item
        if data.key?("value")
          data["value"]
        else
          data
        end
      rescue StandardError => e
        Rails.logger.error("Microsoft Calendar fetch failed: #{e.message}")
        raise
      end
    end
  end
end
