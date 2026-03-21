module Connectors
  module Google
    class WatchSubscriptionService < Connectors::BaseService
      # Register a push notification channel for calendar events
      def register(calendar_id:)
        with_sync_log(operation: "calendar_watch_register") do |log|
          ensure_fresh_token!

          channel_id = SecureRandom.uuid
          channel_token = SecureRandom.hex(32)

          body = {
            id: channel_id,
            type: "web_hook",
            address: webhook_url,
            token: channel_token,
            params: {
              ttl: "604800"
            }
          }

          url = "https://www.googleapis.com/calendar/v3/calendars/#{ERB::Util.url_encode(calendar_id)}/events/watch"
          resp = make_request(:post, url, body)

          if resp.code.to_i == 200
            response_body = JSON.parse(resp.body)
            expiration_ms = response_body["expiration"].to_i
            expires_at = Time.at(expiration_ms / 1000.0)

            subscription = Connectors::WebhookSubscription.create!(
              connector_account_id: connector_account.id,
              provider: "google_calendar",
              calendar_id: calendar_id,
              subscription_id: response_body["id"],
              resource_id: response_body["resourceId"],
              channel_token: channel_token,
              expires_at: expires_at,
              status: "active"
            )

            log.update!(status: "success", records_created: 1)
            success(data: subscription)
          else
            error_msg = "Failed to register watch: #{resp.code} - #{resp.body}"
            log.update!(status: "error", error_message: error_msg)
            failure(errors: [ error_msg ])
          end
        end
      rescue StandardError => e
        failure(errors: [ "Watch registration failed: #{e.message}" ])
      end

      # Stop a push notification channel
      def stop(subscription:)
        ensure_fresh_token!

        body = {
          id: subscription.subscription_id,
          resourceId: subscription.resource_id
        }

        url = "https://www.googleapis.com/calendar/v3/channels/stop"
        resp = make_request(:post, url, body)

        if resp.code.to_i == 204 || resp.code.to_i == 200
          subscription.update!(status: "revoked")
          success(data: subscription)
        else
          failure(errors: [ "Failed to stop watch: #{resp.code}" ])
        end
      rescue StandardError => e
        failure(errors: [ "Stop watch failed: #{e.message}" ])
      end

      private

      def webhook_url
        host = ENV.fetch("APP_HOST", "http://localhost:3000")
        "#{host}/connectors/calendars/google/webhooks"
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
        end

        request["Authorization"] = "Bearer #{connector_account.access_token}"
        request["Content-Type"] = "application/json"
        request.body = body.to_json if body

        http.request(request)
      end
    end
  end
end
