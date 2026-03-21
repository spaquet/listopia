module Connectors
  class RenewWebhookSubscriptionsJob < ApplicationJob
    queue_as :default

    def perform
      Connectors::WebhookSubscription.expiring_soon.find_each do |subscription|
        case subscription.provider
        when "google_calendar"
          renew_google(subscription)
        when "microsoft_outlook"
          renew_microsoft(subscription)
        end
      rescue StandardError => e
        Rails.logger.error("Failed to renew subscription #{subscription.id}: #{e.message}")
      end
    end

    private

    def renew_google(subscription)
      account = subscription.connector_account
      Current.user = account.user
      Current.organization = account.organization

      service = Google::WatchSubscriptionService.new(connector_account: account)
      # Google doesn't support renewing — we must stop and re-register
      service.stop(subscription: subscription)
      service.register(calendar_id: subscription.calendar_id)

      Rails.logger.info("Renewed Google Calendar watch for account #{account.id}")
    ensure
      Current.reset
    end

    def renew_microsoft(subscription)
      account = subscription.connector_account
      Current.user = account.user
      Current.organization = account.organization

      service = Microsoft::SubscriptionService.new(connector_account: account)
      result = service.renew(subscription: subscription)

      if result.success?
        Rails.logger.info("Renewed Microsoft Outlook subscription for account #{account.id}")
      else
        Rails.logger.error("Failed to renew Microsoft subscription: #{result.errors.join(', ')}")
      end
    ensure
      Current.reset
    end
  end
end
