module Connectors
  # Google Drive connector for Listopia
  # Browse and attach files from Google Drive to list items
  class GoogleDrive < BaseConnector
    connector_key "google_drive"
    connector_name "Google Drive"
    connector_category "storage"
    connector_icon "hard-drive"
    connector_description "Browse and attach files from Google Drive to your lists"
    requires_oauth true
    oauth_scopes [
      "https://www.googleapis.com/auth/drive.readonly"
    ]
    settings_schema(
      sync_direction: {
        label: "Sync Direction",
        type: :select,
        options: [ "readonly" ],
        description: "Google Drive is read-only (browsing and attaching files)"
      }
    )

    # Test connection by fetching about info
    def test_connection
      raise "Not connected" unless connected?
      raise "Token expired" if token_expired?

      service = ::Connectors::Google::FileService.new(connector_account: account)
      about = service.fetch_about

      {
        status: "connected",
        message: "Google Drive connection successful",
        user: about["user"]["displayName"],
        quota_mb: (about["storageQuota"]["limit"].to_i / 1_000_000)
      }
    end

    # Pull is not applicable for Google Drive (read-only browsing)
    def pull
      {
        status: "skipped",
        message: "Google Drive connector is read-only (pull not supported)"
      }
    end

    # Push is not applicable for Google Drive (no sync needed)
    def push(data)
      {
        status: "skipped",
        message: "Google Drive connector is read-only (push not supported)"
      }
    end

    private

    def ensure_fresh_token!
      return unless account.token_expired?

      service = ::Connectors::Google::OauthService.new(connector_account: account)
      result = service.refresh_token!

      raise "Token refresh failed: #{result.message}" if result.failure?
    end
  end
end

# Register with connector registry
Connectors::Registry.register(Connectors::GoogleDrive)
