require "rails_helper"

RSpec.describe Connectors::Stub, type: :model do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, creator: user) }
  let(:account) { create(:connectors_account, :with_tokens, provider: "stub", user: user, organization: organization) }

  before do
    Current.user = user
    Current.organization = organization
  end

  after { Current.reset }

  let(:connector) { described_class.new(account) }

  describe "metadata" do
    it "has correct class-level attributes" do
      expect(described_class.key).to eq("stub")
      expect(described_class.name).to eq("Stub Provider (Testing)")
      expect(described_class.category).to eq("testing")
      expect(described_class.oauth_required?).to be true
      expect(described_class.oauth_scopes_list).to eq(["read", "write"])
    end

    it "defines settings schema" do
      schema = described_class.schema
      expect(schema).to have_key(:sync_direction)
      expect(schema).to have_key(:auto_sync)
    end
  end

  describe "#test_connection" do
    it "succeeds when connected with valid token" do
      result = connector.test_connection

      expect(result[:status]).to eq("connected")
      expect(result[:message]).to include("successful")
    end

    it "raises when not connected" do
      account.update!(status: :paused)

      expect {
        connector.test_connection
      }.to raise_error("Not connected")
    end

    it "raises when token is expired" do
      account.update!(token_expires_at: 1.hour.ago)

      expect {
        connector.test_connection
      }.to raise_error("Token expired")
    end
  end

  describe "#pull" do
    it "returns pulled data with success status" do
      result = connector.pull

      expect(result[:status]).to eq("success")
      expect(result[:records_pulled]).to eq(5)
      expect(result[:data]).to be_an(Array)
    end

    it "ensures token is fresh before pulling" do
      account.update!(token_expires_at: 30.minutes.from_now)

      # Mock the token refresh
      allow_any_instance_of(Connectors::Stub::OauthService).to receive(:refresh_token!).and_call_original

      connector.pull

      # Token refresh should have been attempted
      expect(account.reload.token_expires_at).to be_within(2.seconds).of(1.hour.from_now)
    end
  end

  describe "#push" do
    let(:data) do
      [
        { id: "1", title: "Item 1" },
        { id: "2", title: "Item 2" }
      ]
    end

    it "pushes data and returns success" do
      result = connector.push(data)

      expect(result[:status]).to eq("success")
      expect(result[:records_pushed]).to eq(2)
      expect(result[:data]).to eq(data)
    end
  end

  describe "registry integration" do
    it "is registered in the connector registry" do
      expect(Connectors::Registry.find("stub")).to eq(described_class)
    end

    it "appears in list of all connectors" do
      expect(Connectors::Registry.all).to include(described_class)
    end

    it "appears in testing category" do
      expect(Connectors::Registry.by_category("testing")).to include(described_class)
    end
  end
end
