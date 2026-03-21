module Connectors
  class RegisterWebhookJob < BaseJob
    queue_as :default

    def perform(connector_account_id:)
      account = Connectors::Account.find(connector_account_id)
      return unless account.connected?

      Current.user = account.user
      Current.organization = account.organization

      # Get the default calendar ID from settings
      calendar_setting = account.settings.find_by(key: "default_calendar_id")
      calendar_id = calendar_setting&.value || "primary"

      # Register webhook subscription based on provider
      service = case account.provider
      when "google_calendar"
        Google::WatchSubscriptionService.new(connector_account: account)
      when "microsoft_outlook"
        Microsoft::SubscriptionService.new(connector_account: account)
      else
        return
      end

      result = service.register(calendar_id: calendar_id)

      if result.failure?
        Rails.logger.warn("Failed to register webhook for #{account.provider}: #{result.errors.join(', ')}")
      else
        Rails.logger.info("Webhook registered for #{account.provider} calendar")
      end
    rescue StandardError => e
      Rails.logger.error("RegisterWebhookJob error: #{e.message}")
    ensure
      Current.reset
    end
  end
end
