require "rails_helper"

RSpec.describe Connectors::GoogleDrive, type: :model do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, creator: user) }
  let(:account) { create(:connectors_account, :with_tokens, provider: "google_drive", user: user, organization: organization) }

  before do
    Current.user = user
    Current.organization = organization
  end

  after { Current.reset }

  let(:connector) { described_class.new(account) }

  describe "metadata" do
    it "has correct class-level attributes" do
      expect(described_class.key).to eq("google_drive")
      expect(described_class.name).to eq("Google Drive")
      expect(described_class.category).to eq("storage")
      expect(described_class.oauth_required?).to be true
    end

    it "includes Google Drive OAuth scopes" do
      scopes = described_class.oauth_scopes_list
      expect(scopes).to include("https://www.googleapis.com/auth/drive.readonly")
    end

    it "defines settings schema for sync direction" do
      schema = described_class.schema
      expect(schema).to have_key(:sync_direction)
      expect(schema[:sync_direction][:type]).to eq(:select)
    end
  end

  describe "#test_connection" do
    it "tests connection by fetching about info" do
      allow_any_instance_of(Connectors::Google::FileService).to receive(:fetch_about).and_return(
        "user" => { "displayName" => "John Doe" },
        "storageQuota" => { "limit" => "15000000000" }
      )

      result = connector.test_connection

      expect(result[:status]).to eq("connected")
      expect(result[:user]).to eq("John Doe")
      expect(result[:quota_mb]).to eq(15000)
    end

    it "raises error when not connected" do
      account.update!(status: "revoked")
      connector = described_class.new(account)

      expect { connector.test_connection }.to raise_error("Not connected")
    end

    it "raises error when token expired" do
      account.update!(token_expires_at: 1.hour.ago)
      connector = described_class.new(account)

      expect { connector.test_connection }.to raise_error("Token expired")
    end
  end

  describe "#pull" do
    it "returns skipped status for pull operation" do
      result = connector.pull

      expect(result[:status]).to eq("skipped")
      expect(result[:message]).to include("read-only")
    end
  end

  describe "#push" do
    it "returns skipped status for push operation" do
      result = connector.push([])

      expect(result[:status]).to eq("skipped")
      expect(result[:message]).to include("read-only")
    end
  end

  describe "registry integration" do
    it "is registered in the connector registry" do
      expect(Connectors::Registry.find("google_drive")).to eq(described_class)
    end

    it "appears in storage category" do
      expect(Connectors::Registry.by_category("storage")).to include(described_class)
    end
  end
end
