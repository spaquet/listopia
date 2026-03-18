module Connectors
  # Google Calendar connector for Listopia
  # Syncs events between Google Calendar and Listopia items
  class GoogleCalendar < BaseConnector
    connector_key "google_calendar"
    connector_name "Google Calendar"
    connector_category "calendars"
    connector_icon "calendar"
    connector_description "Sync events between Google Calendar and your lists"
    requires_oauth true
    oauth_scopes [
      "https://www.googleapis.com/auth/calendar",
      "https://www.googleapis.com/auth/calendar.events"
    ]
    settings_schema(
      default_calendar_id: {
        label: "Default Calendar",
        type: :select,
        options: [],  # Populated dynamically from connected calendars
        description: "Calendar to sync with"
      },
      sync_direction: {
        label: "Sync Direction",
        type: :select,
        options: [ "pull", "push", "both" ],
        description: "Direction of event sync"
      },
      auto_sync: {
        label: "Auto Sync",
        type: :boolean,
        description: "Automatically sync events on schedule"
      }
    )

    # Test connection by listing calendars
    def test_connection
      raise "Not connected" unless connected?
      raise "Token expired" if token_expired?

      service = Google::CalendarFetchService.new(connector_account: account)
      calendars = service.fetch_calendars

      {
        status: "connected",
        message: "Google Calendar connection successful",
        calendars_count: calendars.count
      }
    end

    # Pull events from Google Calendar to Listopia
    def pull
      ensure_fresh_token!

      service = Google::EventSyncService.new(connector_account: account)
      result = service.pull_events

      {
        status: "success",
        records_pulled: result[:count],
        data: result[:events]
      }
    end

    # Push events from Listopia to Google Calendar
    def push(data)
      ensure_fresh_token!

      service = Google::EventSyncService.new(connector_account: account)
      result = service.push_events(data)

      {
        status: "success",
        records_pushed: result[:count],
        data: result[:events]
      }
    end

    private

    def ensure_fresh_token!
      return unless account.token_expired?

      service = Google::OauthService.new(connector_account: account)
      result = service.refresh_token!

      raise "Token refresh failed: #{result.message}" if result.failure?
    end
  end
end

# Register with connector registry
Connectors::Registry.register(Connectors::GoogleCalendar)
