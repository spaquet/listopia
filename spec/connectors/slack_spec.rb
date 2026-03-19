require "rails_helper"

RSpec.describe Connectors::Slack, type: :model do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, creator: user) }
  let(:account) { create(:connectors_account, :with_tokens, provider: "slack", user: user, organization: organization) }

  before do
    Current.user = user
    Current.organization = organization
  end

  after { Current.reset }

  let(:connector) { described_class.new(account) }

  describe "metadata" do
    it "has correct class-level attributes" do
      expect(described_class.key).to eq("slack")
      expect(described_class.name).to eq("Slack")
      expect(described_class.category).to eq("messaging")
      expect(described_class.oauth_required?).to be true
    end

    it "includes Slack OAuth scopes" do
      scopes = described_class.oauth_scopes_list
      expect(scopes).to include("chat:write")
      expect(scopes).to include("channels:read")
      expect(scopes).to include("users:read")
    end

    it "defines settings schema with channel selection and posting options" do
      schema = described_class.schema
      expect(schema).to have_key(:default_channel_id)
      expect(schema).to have_key(:post_on_completion)
      expect(schema).to have_key(:post_on_creation)
    end
  end

  describe "#test_connection" do
    it "tests connection by fetching channels" do
      allow_any_instance_of(Connectors::Messaging::Slack::MessageService).to receive(:fetch_channels).and_return([
        { "id" => "C123", "name" => "general" },
        { "id" => "C456", "name" => "random" }
      ])

      result = connector.test_connection

      expect(result[:status]).to eq("connected")
      expect(result[:channels_count]).to eq(2)
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
      expect(result[:message]).to include("send-only")
    end
  end

  describe "#push" do
    it "pushes messages to Slack channel" do
      allow_any_instance_of(Connectors::Messaging::Slack::MessageService).to receive(:post_messages).and_return(
        count: 2,
        messages: [
          { id: "ts1", text: "Task 1" },
          { id: "ts2", text: "Task 2" }
        ]
      )

      data = [
        { title: "Task 1", status: "created" },
        { title: "Task 2", status: "completed" }
      ]

      result = connector.push(data)

      expect(result[:status]).to eq("success")
      expect(result[:records_pushed]).to eq(2)
    end
  end

  describe "registry integration" do
    it "is registered in the connector registry" do
      expect(Connectors::Registry.find("slack")).to eq(described_class)
    end

    it "appears in messaging category" do
      expect(Connectors::Registry.by_category("messaging")).to include(described_class)
    end
  end
end
