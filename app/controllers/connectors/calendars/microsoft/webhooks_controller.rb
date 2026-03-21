module Connectors
  module Calendars
    module Microsoft
      class WebhooksController < ActionController::Base
        # Webhook endpoint called by Microsoft Graph API (third-party service)
        # CSRF protection disabled because:
        # 1. Webhooks are called by external APIs, not browsers (no CSRF tokens)
        # 2. Authentication uses cryptographic token in request body (clientState)
        # 3. :null_session clears session on validation failure (prevents hijacking)
        # 4. This follows Rails security guidelines for webhook endpoints
        protect_from_forgery with: :null_session

        # GET/POST /connectors/calendars/microsoft/webhooks
        # Microsoft first sends a GET with validationToken query param for validation.
        # We must echo it back as plain text within 10 seconds.
        # Then it sends POST requests with actual change notifications.
        def receive
          # Validation handshake from Microsoft
          if params[:validationToken].present?
            return render plain: params[:validationToken], content_type: "text/plain", status: :ok
          end

          # Process actual change notifications
          notifications = params[:value] || []

          notifications.each do |notification|
            subscription_id = notification["subscriptionId"]
            client_state = notification["clientState"]
            subscription = Connectors::WebhookSubscription.find_by(subscription_id: subscription_id)

            # Verify subscription exists, is active, and token matches
            next unless subscription&.active? && subscription.channel_token == client_state

            # Trigger a full sync for this calendar account
            Connectors::CalendarEventSyncJob.perform_later(
              connector_account_id: subscription.connector_account_id
            )
          end

          # Always return 202 Accepted — Microsoft doesn't care about response body
          head :accepted
        rescue StandardError => e
          Rails.logger.error("Microsoft calendar webhook error: #{e.message}\n#{e.backtrace.join("\n")}")
          head :accepted
        end
      end
    end
  end
end
