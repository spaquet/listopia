module Connectors
  # Background job to sync calendar events from connector accounts
  class CalendarEventSyncJob < Connectors::BaseJob
    protected

    def call
      # Support both google_calendar and microsoft_outlook
      return unless %w[google_calendar microsoft_outlook].include?(connector_account.provider)
      return unless connector_account.active?

      # Set Current context for authorization
      Current.user = connector_account.user
      Current.organization = connector_account.organization

      begin
        service = Connectors::CalendarEventSyncService.new(
          connector_account: connector_account
        )

        result = service.call

        if result.success?
          Rails.logger.info("Calendar event sync completed: #{result.data[:synced]} events synced")
        else
          Rails.logger.warn("Calendar event sync failed: #{result.message}")
        end
      ensure
        Current.reset
      end
    end
  end
end
