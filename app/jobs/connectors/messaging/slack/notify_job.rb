module Connectors
  module Messaging
    module Slack
      # Post item updates to Slack
      class NotifyJob < Connectors::BaseJob
        protected

        def call(event_type:, item_id:, **options)
          return unless connector_account.provider == "slack"
          return unless connector_account.active?

          # Check if notification is enabled for this event
          setting_key = case event_type
          when "completed"
            "post_on_completion"
          when "created"
            "post_on_creation"
          else
            nil
          end

          return unless setting_key

          enabled = connector_account.settings.find_by(key: setting_key)&.value == "true"
          return unless enabled

          # Set Current context
          Current.user = connector_account.user
          Current.organization = connector_account.organization

          begin
            # Fetch the item (adjust based on your List structure)
            item = ::ListItem.find(item_id)

            service = ::Connectors::Messaging::Slack::MessageService.new(
              connector_account: connector_account
            )

            # Build notification message
            message_text = "#{emoji_for_event(event_type)} *#{item.title}*\nList: #{item.list.title}"

            service.post_message(
              connector_account.settings.find_by(key: "default_channel_id")&.value || "general",
              message_text
            )

            Rails.logger.info("Slack notification sent for item #{item_id}")
          rescue StandardError => e
            Rails.logger.error("Failed to send Slack notification: #{e.message}")
          ensure
            Current.reset
          end
        end

        private

        def emoji_for_event(event_type)
          case event_type
          when "completed"
            "✅"
          when "created"
            "✨"
          else
            "📌"
          end
        end
      end
    end
  end
end
