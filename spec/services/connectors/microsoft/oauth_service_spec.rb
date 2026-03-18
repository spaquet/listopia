require "rails_helper"

RSpec.describe Connectors::Microsoft::OauthService, type: :service do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, creator: user) }

  before do
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:microsoft_outlook, :client_id).and_return("test_client_id")
    allow(Rails.application.credentials).to receive(:dig).with(:microsoft_outlook, :client_secret).and_return("test_client_secret")
  end

  describe "#authorization_url" do
    let(:service) { described_class.new }

    it "generates Microsoft OAuth authorization URL with PKCE" do
      redirect_uri = "https://example.com/callback"
      state = "random_state_123"

      url = service.authorization_url(redirect_uri: redirect_uri, state: state)

      expect(url).to include(described_class::OAUTH_AUTH_URL)
      expect(url).to include("client_id=test_client_id")
      expect(url).to include("state=#{state}")
      expect(url).to include("code_challenge")
      expect(url).to include("code_challenge_method=S256")
    end

    it "includes Outlook Calendar scopes" do
      url = service.authorization_url(redirect_uri: "https://example.com/callback", state: "state")

      expect(url).to include("Calendars.Read")
      expect(url).to include("Calendars.ReadWrite")
    end
  end

  describe "#exchange_code!" do
    let(:service) { described_class.new }
    let(:code) { "auth_code_abc123" }
    let(:redirect_uri) { "https://example.com/callback" }

    context "with valid code" do
      before do
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
          instance_double(Net::HTTPSuccess,
            is_a?: true,
            body: {
              access_token: "access_token_123",
              refresh_token: "refresh_token_456",
              expires_in: 3600
            }.to_json
          )
        )

        # Mock user info fetch
        allow(service).to receive(:fetch_user_info).and_return({
          "id" => "microsoft_user_123",
          "displayName" => "John Doe",
          "userPrincipalName" => "john@example.com"
        })
      end

      it "creates connector account and returns success" do
        result = service.exchange_code!(code, redirect_uri, user, organization)

        expect(result.success?).to be true
        expect(result.data).to be_a(Connectors::Account)
        expect(result.data.provider).to eq("microsoft_outlook")
        expect(result.data.status).to eq("active")
      end

      it "saves encrypted tokens" do
        result = service.exchange_code!(code, redirect_uri, user, organization)

        account = result.data
        expect(account.access_token).to eq("access_token_123")
        expect(account.refresh_token).to eq("refresh_token_456")
      end
    end
  end

  describe "#refresh_token!" do
    let(:account) { create(:connectors_account, :with_tokens, provider: "microsoft_outlook", user: user, organization: organization) }
    let(:service) { described_class.new(connector_account: account) }

    before do
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
        instance_double(Net::HTTPSuccess,
          is_a?: true,
          body: {
            access_token: "new_access_token",
            expires_in: 3600
          }.to_json
        )
      )
    end

    it "refreshes token successfully" do
      result = service.refresh_token!

      expect(result.success?).to be true
      expect(account.reload.access_token).to eq("new_access_token")
    end
  end
end
