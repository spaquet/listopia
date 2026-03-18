module Connectors
  # Stub connector for testing OAuth flows and connector patterns
  # Simulates a complete connector without external API dependencies
  class Stub < BaseConnector
    connector_key "stub"
    connector_name "Stub Provider (Testing)"
    connector_category "testing"
    connector_icon "settings"
    connector_description "Testing connector for verifying OAuth and sync flows"
    requires_oauth true
    oauth_scopes ["read", "write"]
    settings_schema(
      sync_direction: {
        label: "Sync Direction",
        type: :select,
        options: ["push", "pull", "both"],
        description: "Direction of data sync"
      },
      auto_sync: {
        label: "Auto Sync",
        type: :boolean,
        description: "Enable automatic sync"
      }
    )

    # Test the connection by verifying tokens are valid
    def test_connection
      raise "Not connected" unless connected?
      raise "Token expired" if token_expired?

      { status: "connected", message: "Stub provider connection successful" }
    end

    # Pull data from the provider (stub returns fake data)
    def pull
      ensure_fresh_token!

      # Simulate pulling data from provider
      {
        status: "success",
        records_pulled: 5,
        data: [
          { id: "stub_1", title: "Test Item 1" },
          { id: "stub_2", title: "Test Item 2" }
        ]
      }
    end

    # Push data to the provider (stub simulates success)
    def push(data)
      ensure_fresh_token!

      # Simulate pushing data to provider
      {
        status: "success",
        records_pushed: data.count,
        data: data
      }
    end

    private

    def ensure_fresh_token!
      return unless account.token_expired?

      service = Stub::OauthService.new(connector_account: account)
      result = service.refresh_token!

      raise "Token refresh failed" unless result.success?
    end
  end
end

# Register stub connector
Connectors::Registry.register(Connectors::Stub)
