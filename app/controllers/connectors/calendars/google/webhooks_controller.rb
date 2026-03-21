module Connectors
  module Calendars
    module Google
      class WebhooksController < ActionController::Base
        protect_from_forgery with: :null_session
        before_action :verify_channel_token

        # POST /connectors/calendars/google/webhooks
        # Handles Google Calendar push notifications
        def receive
          resource_state = request.headers["X-Goog-Resource-State"]

          # "sync" is the initial handshake after registering the watch — just acknowledge
          return head :ok if resource_state == "sync"

          channel_id = request.headers["X-Goog-Channel-ID"]
          subscription = Connectors::WebhookSubscription.find_by(subscription_id: channel_id)

          if subscription&.active?
            # Trigger a full sync for this calendar account
            Connectors::CalendarEventSyncJob.perform_later(
              connector_account_id: subscription.connector_account_id
            )
          end

          head :ok
        rescue StandardError => e
          Rails.logger.error("Google calendar webhook error: #{e.message}\n#{e.backtrace.join("\n")}")
          head :ok
        end

        private

        def verify_channel_token
          channel_id = request.headers["X-Goog-Channel-ID"]
          token = request.headers["X-Goog-Channel-Token"]
          subscription = Connectors::WebhookSubscription.find_by(subscription_id: channel_id)

          unless subscription&.channel_token == token
            head :unauthorized
          end
        end
      end
    end
  end
end
