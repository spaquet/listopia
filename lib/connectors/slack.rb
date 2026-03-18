module Connectors
  # Slack connector for Listopia
  # Posts messages to Slack channels and receives webhook events
  class Slack < BaseConnector
    connector_key "slack"
    connector_name "Slack"
    connector_category "messaging"
    connector_icon "message-square"
    connector_description "Post completed items and updates to Slack channels"
    requires_oauth true
    oauth_scopes [
      "chat:write",
      "channels:read",
      "users:read"
    ]
    settings_schema(
      default_channel_id: {
        label: "Default Channel",
        type: :select,
        options: [],  # Populated dynamically from connected workspace
        description: "Channel to post messages to"
      },
      post_on_completion: {
        label: "Post on Item Completion",
        type: :boolean,
        description: "Automatically post to Slack when items are completed"
      },
      post_on_creation: {
        label: "Post on Item Creation",
        type: :boolean,
        description: "Automatically post to Slack when new items are created"
      }
    )

    # Test connection by fetching channels
    def test_connection
      raise "Not connected" unless connected?
      raise "Token expired" if token_expired?

      service = ::Connectors::Messaging::Slack::MessageService.new(connector_account: account)
      channels = service.fetch_channels

      {
        status: "connected",
        message: "Slack workspace connection successful",
        channels_count: channels.count
      }
    end

    # Pull is not applicable for Slack (one-way messaging)
    def pull
      {
        status: "skipped",
        message: "Slack connector is send-only (pull not supported)"
      }
    end

    # Push messages to Slack
    def push(data)
      ensure_fresh_token!

      service = ::Connectors::Messaging::Slack::MessageService.new(connector_account: account)
      result = service.post_messages(data)

      {
        status: "success",
        records_pushed: result[:count],
        data: result[:messages]
      }
    end

    private

    def ensure_fresh_token!
      # Slack tokens typically don't expire, but implement for consistency
      return unless account.token_expired?

      service = ::Connectors::Messaging::Slack::OauthService.new(connector_account: account)
      result = service.refresh_token!

      raise "Token refresh failed: #{result.message}" if result.failure?
    end
  end
end

# Register with connector registry
Connectors::Registry.register(Connectors::Slack)
