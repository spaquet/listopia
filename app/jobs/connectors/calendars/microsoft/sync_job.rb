module Connectors
  module Calendars
    module Microsoft
      # Background job to sync Outlook Calendar events
      class SyncJob < Connectors::BaseJob
        protected

        def call
          return unless connector_account.provider == "microsoft_outlook"
          return unless connector_account.active?

          # Set Current context for authorization
          Current.user = connector_account.user
          Current.organization = connector_account.organization

          begin
            service = ::Connectors::Microsoft::EventSyncService.new(
              connector_account: connector_account
            )

            # Pull events from Outlook
            result = service.pull_events

            Rails.logger.info("Outlook Calendar sync completed: #{result[:count]} events")
          ensure
            Current.reset
          end
        end
      end
    end
  end
end
