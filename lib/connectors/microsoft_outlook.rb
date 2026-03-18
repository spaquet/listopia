module Connectors
  # Microsoft Outlook Calendar connector for Listopia
  # Syncs events between Outlook and Listopia items via Microsoft Graph API
  class MicrosoftOutlook < BaseConnector
    connector_key "microsoft_outlook"
    connector_name "Microsoft Outlook Calendar"
    connector_category "calendars"
    connector_icon "calendar"
    connector_description "Sync events between Outlook Calendar and your lists"
    requires_oauth true
    oauth_scopes [
      "Calendars.Read",
      "Calendars.ReadWrite",
      "offline_access"
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

      service = Microsoft::CalendarFetchService.new(connector_account: account)
      calendars = service.fetch_calendars

      {
        status: "connected",
        message: "Outlook Calendar connection successful",
        calendars_count: calendars.count
      }
    end

    # Pull events from Outlook to Listopia
    def pull
      ensure_fresh_token!

      service = Microsoft::EventSyncService.new(connector_account: account)
      result = service.pull_events

      {
        status: "success",
        records_pulled: result[:count],
        data: result[:events]
      }
    end

    # Push events from Listopia to Outlook
    def push(data)
      ensure_fresh_token!

      service = Microsoft::EventSyncService.new(connector_account: account)
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

      service = Microsoft::OauthService.new(connector_account: account)
      result = service.refresh_token!

      raise "Token refresh failed: #{result.message}" if result.failure?
    end
  end
end

# Register with connector registry
Connectors::Registry.register(Connectors::MicrosoftOutlook)
