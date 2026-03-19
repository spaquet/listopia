module Connectors
  module Calendars
    module Google
      # Background job to sync Google Calendar events
      class SyncJob < Connectors::BaseJob
        protected

        def call
          return unless connector_account.provider == "google_calendar"
          return unless connector_account.active?

          # Set Current context for authorization
          Current.user = connector_account.user
          Current.organization = connector_account.organization

          begin
            service = ::Connectors::Google::EventSyncService.new(
              connector_account: connector_account
            )

            # Pull events from Google Calendar
            result = service.pull_events

            Rails.logger.info("Google Calendar sync completed: #{result[:count]} events")
          ensure
            Current.reset
          end
        end
      end
    end
  end
end
