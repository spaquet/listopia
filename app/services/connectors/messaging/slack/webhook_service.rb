module Connectors
  module Messaging
    module Slack
      # Handle incoming Slack webhook events
      # https://api.slack.com/apis/connections/events-api
      class WebhookService < Connectors::BaseService
      # Verify Slack request signature
      def self.verify_request(timestamp, signature, body)
        # Slack signature format: v0=<hash>
        unless signature.present? && timestamp.present?
          return false
        end

        # Check timestamp is recent (within 5 minutes)
        request_time = timestamp.to_i
        current_time = Time.current.to_i

        return false if (current_time - request_time).abs > 300  # 5 minutes

        # Verify signature
        signing_secret = Rails.application.credentials.dig(:slack, :signing_secret) ||
          ENV["SLACK_SIGNING_SECRET"] ||
          return false

        base_string = "v0:#{timestamp}:#{body}"
        computed_signature = "v0=#{OpenSSL::HMAC.hexdigest("SHA256", signing_secret, base_string)}"

        secure_compare(computed_signature, signature)
      end

      # Handle URL verification challenge from Slack
      def self.handle_verification(payload)
        if payload["type"] == "url_verification"
          { challenge: payload["challenge"] }
        else
          nil
        end
      end

      # Handle event from Slack
      def handle_event(event_payload)
        return unless connector_account.active?

        event = event_payload["event"]
        event_type = event["type"]

        case event_type
        when "message"
          handle_message_event(event)
        when "reaction_added"
          handle_reaction_event(event)
        when "app_mention"
          handle_mention_event(event)
        else
          Rails.logger.debug("Slack event type not handled: #{event_type}")
        end

        { ok: true }
      end

      private

      def handle_message_event(event)
        Rails.logger.info("Slack message: #{event}")
        # Implement custom message handling if needed
      end

      def handle_reaction_event(event)
        Rails.logger.info("Slack reaction: #{event}")
        # Implement custom reaction handling if needed
      end

      def handle_mention_event(event)
        Rails.logger.info("Slack mention: #{event}")
        # Implement custom mention handling if needed
      end

      # Constant-time string comparison to prevent timing attacks
      def self.secure_compare(a, b)
        return false unless a.is_a?(String) && b.is_a?(String)
        return false if a.bytesize != b.bytesize

        l = a.unpack "C#{a.bytesize}"
        r = b.unpack "C#{b.bytesize}"
        result = 0

        l.each_with_index { |byte, index| result |= byte ^ r[index] }
        result == 0
      end
    end
  end
end
