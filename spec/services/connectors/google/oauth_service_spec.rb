require "rails_helper"

RSpec.describe Connectors::Google::OauthService, type: :service do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, creator: user) }

  before do
    # Mock Google credentials
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:google_calendar, :client_id).and_return("test_client_id")
    allow(Rails.application.credentials).to receive(:dig).with(:google_calendar, :client_secret).and_return("test_client_secret")
  end

  describe "#authorization_url" do
    let(:service) { described_class.new }

    it "generates Google OAuth authorization URL with state parameter" do
      redirect_uri = "https://example.com/callback"
      state = "random_state_123"

      url = service.authorization_url(redirect_uri: redirect_uri, state: state)

      expect(url).to include(described_class::OAUTH_AUTH_URL)
      expect(url).to include("client_id=test_client_id")
      expect(url).to include("redirect_uri=")
      expect(url).to include("state=#{state}")
      expect(url).to include("access_type=offline")
      expect(url).to include("prompt=consent")
    end

    it "includes Google Calendar scopes" do
      url = service.authorization_url(redirect_uri: "https://example.com/callback", state: "state")

      expect(url).to include(URI.encode_www_form_component(Connectors::GoogleCalendar.oauth_scopes_list.join(" ")))
    end
  end

  describe "#exchange_code!" do
    let(:service) { described_class.new }
    let(:code) { "auth_code_abc123" }
    let(:redirect_uri) { "https://example.com/callback" }

    context "with valid code" do
      before do
        # Mock successful token response
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
          instance_double(Net::HTTPSuccess,
            is_a?: true,
            body: {
              access_token: "access_token_123",
              refresh_token: "refresh_token_456",
              expires_in: 3600,
              id_token: "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJnb29nbGVfdXNlcl8xMjMiLCJuYW1lIjoiSm9obiBEb2UiLCJlbWFpbCI6ImJpbGxAZXhhbXBsZS5jb20ifQ.EL4f-m9ZlyPYg7I2Qw0Lz_9oKdJd6-dxYL5hh_YXRLY"
            }.to_json
          )
        )
      end

      it "creates connector account and returns success" do
        result = service.exchange_code!(code, redirect_uri, user, organization)

        expect(result.success?).to be true
        expect(result.data).to be_a(Connectors::Account)
        expect(result.data.provider).to eq("google_calendar")
        expect(result.data.status).to eq("active")
      end

      it "saves encrypted tokens with expiration" do
        result = service.exchange_code!(code, redirect_uri, user, organization)

        account = result.data
        expect(account.access_token).to eq("access_token_123")
        expect(account.refresh_token).to eq("refresh_token_456")
        expect(account.token_expires_at).to be_within(2.seconds).of(1.hour.from_now)
      end
    end

    context "with invalid code" do
      it "returns failure for empty code" do
        result = service.exchange_code!("", redirect_uri, user, organization)

        expect(result.failure?).to be true
      end
    end
  end

  describe "#refresh_token!" do
    let(:account) { create(:connectors_account, :with_tokens, provider: "google_calendar", user: user, organization: organization) }
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

    it "refreshes token and returns success" do
      old_token = account.access_token

      result = service.refresh_token!

      expect(result.success?).to be true
      expect(account.reload.access_token).to eq("new_access_token")
    end

    it "updates token expiration" do
      service.refresh_token!

      expect(account.reload.token_expires_at).to be_within(2.seconds).of(1.hour.from_now)
    end
  end
end
