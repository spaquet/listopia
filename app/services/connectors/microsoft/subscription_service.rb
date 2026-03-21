module Connectors
  module Microsoft
    class SubscriptionService < Connectors::BaseService
      # Register a change notification subscription for calendar events
      def register(calendar_id:)
        with_sync_log(operation: "calendar_subscription_register") do |log|
          ensure_fresh_token!

          channel_token = SecureRandom.hex(32)
          expiration_time = 3.days.from_now

          body = {
            changeType: "created,updated,deleted",
            notificationUrl: webhook_url,
            resource: "/me/calendars/#{calendar_id}/events",
            expirationDateTime: expiration_time.iso8601,
            clientState: channel_token
          }

          url = "https://graph.microsoft.com/v1.0/subscriptions"
          resp = make_request(:post, url, body)

          if resp.code.to_i == 201
            response_body = JSON.parse(resp.body)
            expires_at = Time.parse(response_body["expirationDateTime"])

            subscription = Connectors::WebhookSubscription.create!(
              connector_account_id: connector_account.id,
              provider: "microsoft_outlook",
              calendar_id: calendar_id,
              subscription_id: response_body["id"],
              channel_token: channel_token,
              expires_at: expires_at,
              status: "active"
            )

            log.update!(status: "success", records_created: 1)
            success(data: subscription)
          else
            error_msg = "Failed to register subscription: #{resp.code} - #{resp.body}"
            log.update!(status: "error", error_message: error_msg)
            failure(errors: [ error_msg ])
          end
        end
      rescue StandardError => e
        failure(errors: [ "Subscription registration failed: #{e.message}" ])
      end

      # Renew an existing subscription before it expires
      def renew(subscription:)
        ensure_fresh_token!

        expiration_time = 3.days.from_now
        body = {
          expirationDateTime: expiration_time.iso8601
        }

        url = "https://graph.microsoft.com/v1.0/subscriptions/#{subscription.subscription_id}"
        resp = make_request(:patch, url, body)

        if resp.code.to_i == 200
          response_body = JSON.parse(resp.body)
          expires_at = Time.parse(response_body["expirationDateTime"])
          subscription.update!(expires_at: expires_at)
          success(data: subscription)
        else
          failure(errors: [ "Failed to renew subscription: #{resp.code}" ])
        end
      rescue StandardError => e
        failure(errors: [ "Subscription renewal failed: #{e.message}" ])
      end

      # Stop a subscription
      def stop(subscription:)
        ensure_fresh_token!

        url = "https://graph.microsoft.com/v1.0/subscriptions/#{subscription.subscription_id}"
        resp = make_request(:delete, url)

        if resp.code.to_i == 204 || resp.code.to_i == 200
          subscription.update!(status: "revoked")
          success(data: subscription)
        else
          failure(errors: [ "Failed to stop subscription: #{resp.code}" ])
        end
      rescue StandardError => e
        failure(errors: [ "Stop subscription failed: #{e.message}" ])
      end

      private

      def webhook_url
        host = ENV.fetch("APP_HOST", "http://localhost:3000")
        "#{host}/connectors/calendars/microsoft/webhooks"
      end

      def make_request(method, url, body = nil)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"

        request = case method
        when :post
          Net::HTTP::Post.new(uri.request_uri)
        when :patch
          Net::HTTP::Patch.new(uri.request_uri)
        when :delete
          Net::HTTP::Delete.new(uri.request_uri)
        end

        request["Authorization"] = "Bearer #{connector_account.access_token}"
        request["Content-Type"] = "application/json"
        request.body = body.to_json if body

        http.request(request)
      end
    end
  end
end
