require "rails_helper"

RSpec.describe Connectors::Slack::OauthService, type: :service do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, creator: user) }

  before do
    # Mock Slack credentials
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:slack, :client_id).and_return("test_client_id")
    allow(Rails.application.credentials).to receive(:dig).with(:slack, :client_secret).and_return("test_client_secret")
  end

  describe "#authorization_url" do
    let(:service) { described_class.new }

    it "generates Slack OAuth authorization URL with user scope" do
      redirect_uri = "https://example.com/callback"
      state = "random_state_123"

      url = service.authorization_url(redirect_uri: redirect_uri, state: state)

      expect(url).to include(described_class::OAUTH_AUTH_URL)
      expect(url).to include("client_id=test_client_id")
      expect(url).to include("redirect_uri=")
      expect(url).to include("state=#{state}")
      expect(url).to include("user_scope=users:read")
    end

    it "includes Slack message posting scopes" do
      url = service.authorization_url(redirect_uri: "https://example.com/callback", state: "state")

      expect(url).to include(URI.encode_www_form_component(Connectors::Slack.oauth_scopes_list.join(",")))
    end
  end

  describe "#exchange_code!" do
    let(:service) { described_class.new }
    let(:code) { "xoxb-abc123def456" }
    let(:redirect_uri) { "https://example.com/callback" }

    context "with valid code" do
      before do
        # Mock successful token response
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
          instance_double(Net::HTTPSuccess,
            is_a?: true,
            body: {
              ok: true,
              access_token: "xoxb-access-token-123",
              token_type: "bot",
              scope: "chat:write,channels:read,users:read",
              bot_user_id: "U12345",
              app_id: "A67890",
              team: { name: "Test Workspace", id: "T11111" },
              enterprise: nil,
              user_id: "U99999"
            }.to_json
          )
        )
      end

      it "creates connector account and returns success" do
        result = service.exchange_code!(code, redirect_uri, user, organization)

        expect(result.success?).to be true
        expect(result.data).to be_a(Connectors::Account)
        expect(result.data.provider).to eq("slack")
        expect(result.data.status).to eq("active")
      end

      it "saves access token without refresh token" do
        result = service.exchange_code!(code, redirect_uri, user, organization)

        account = result.data
        expect(account.access_token).to eq("xoxb-access-token-123")
        expect(account.refresh_token).to be_nil
        expect(account.token_expires_at).to be_nil
      end

      it "stores workspace info in metadata" do
        result = service.exchange_code!(code, redirect_uri, user, organization)

        account = result.data
        expect(account.metadata["app_id"]).to eq("A67890")
        expect(account.metadata["team_id"]).to eq("T11111")
        expect(account.metadata["team_name"]).to eq("Test Workspace")
      end

      it "stores display name and email from workspace" do
        result = service.exchange_code!(code, redirect_uri, user, organization)

        account = result.data
        expect(account.display_name).to eq("Test Workspace")
        expect(account.email).to eq("U99999")
      end
    end

    context "with invalid code" do
      it "returns failure for empty code" do
        result = service.exchange_code!("", redirect_uri, user, organization)

        expect(result.failure?).to be true
      end
    end

    context "with API error response" do
      before do
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
          instance_double(Net::HTTPSuccess,
            is_a?: true,
            body: {
              ok: false,
              error: "invalid_code"
            }.to_json
          )
        )
      end

      it "returns failure with error message" do
        result = service.exchange_code!(code, redirect_uri, user, organization)

        expect(result.failure?).to be true
        expect(result.message).to include("authorization failed")
      end
    end
  end

  describe "#refresh_token!" do
    let(:account) { create(:connectors_account, :with_tokens, provider: "slack", user: user, organization: organization) }
    let(:service) { described_class.new(connector_account: account) }

    it "returns success with no_refresh_needed status for Slack bot tokens" do
      result = service.refresh_token!

      expect(result.success?).to be true
      expect(result.data[:status]).to eq("no_refresh_needed")
    end
  end
end
