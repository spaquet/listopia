module Connectors
  module Messaging
    module Slack
      # Handle incoming Slack webhook events
      class WebhooksController < ActionController::Base
        before_action :verify_slack_signature

        protect_from_forgery with: :null_session

        # POST /connectors/messaging/slack/webhooks
        def receive
          # Handle URL verification challenge from Slack
          challenge_response = ::Connectors::Slack::WebhookService.handle_verification(params.to_unsafe_h)
          return render json: challenge_response if challenge_response.present?

          # Handle actual event
          begin
            payload = params.to_unsafe_h
            event_payload = payload["event"]

            if event_payload.present?
              # Find connector account by workspace ID
              workspace_id = payload["team_id"]
              connector_account = ::Connectors::Account.find_by(
                provider: "slack",
                provider_uid: workspace_id
              )

              if connector_account
                service = ::Connectors::Slack::WebhookService.new(connector_account: connector_account)
                result = service.handle_event(payload)
                render json: result
              else
                render json: { ok: true }, status: :ok
              end
            else
              render json: { ok: true }, status: :ok
            end
          rescue StandardError => e
            Rails.logger.error("Slack webhook error: #{e.message}")
            render json: { ok: true }, status: :ok
          end
        end

        private

        def verify_slack_signature
          timestamp = request.headers["X-Slack-Request-Timestamp"]
          signature = request.headers["X-Slack-Signature"]
          body = request.body.read

          # Reset body for params parsing
          request.body.rewind

          unless ::Connectors::Slack::WebhookService.verify_request(timestamp, signature, body)
            render json: { error: "Unauthorized" }, status: :unauthorized
          end
        end
      end
    end
  end
end
