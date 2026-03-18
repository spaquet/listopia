require "rails_helper"

RSpec.describe Connectors::Stub::OauthService, type: :service do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, creator: user) }
  let(:service) { described_class.new }

  describe "#authorization_url" do
    it "returns a valid authorization URL with state parameter" do
      redirect_uri = "https://example.com/callback"
      state = "random_state_123"

      url = service.authorization_url(redirect_uri: redirect_uri, state: state)

      expect(url).to include(described_class::STUB_AUTH_URL)
      expect(url).to include("client_id=#{described_class::STUB_CLIENT_ID}")
      expect(url).to include("redirect_uri=#{CGI.escape(redirect_uri)}")
      expect(url).to include("state=#{state}")
      expect(url).to include("response_type=code")
    end
  end

  describe "#exchange_code!" do
    let(:code) { "auth_code_123" }
    let(:redirect_uri) { "https://example.com/callback" }

    context "with valid code" do
      it "creates connector account and returns success" do
        Current.user = user
        Current.organization = organization

        result = service.exchange_code!(code, redirect_uri, user, organization)

        expect(result.success?).to be true
        expect(result.data).to be_a(Connectors::Account)
        expect(result.data.user_id).to eq(user.id)
        expect(result.data.provider).to eq("stub")
        expect(result.data.status).to eq("active")
      end

      it "saves access and refresh tokens with expiration" do
        result = service.exchange_code!(code, redirect_uri, user, organization)

        account = result.data
        expect(account.access_token).to be_present
        expect(account.refresh_token).to be_present
        expect(account.token_expires_at).to be_within(2.seconds).of(1.hour.from_now)
      end

      it "extracts user ID from code if present" do
        code_with_user = "auth_code_user:custom_user_123"

        result = service.exchange_code!(code_with_user, redirect_uri, user, organization)

        account = result.data
        expect(account.provider_uid).to eq("custom_user_123")
      end
    end

    context "with invalid code" do
      it "returns failure for empty code" do
        result = service.exchange_code!("", redirect_uri, user, organization)

        expect(result.failure?).to be true
        expect(result.message).to include("Authorization failed")
      end

      it "returns failure for specific invalid code" do
        result = service.exchange_code!("invalid_code", redirect_uri, user, organization)

        expect(result.failure?).to be true
      end
    end
  end

  describe "#refresh_token!" do
    let(:account) { create(:connectors_account, :with_tokens, provider: "stub", user: user, organization: organization) }
    let(:service) { described_class.new(connector_account: account) }

    context "when refresh token is valid" do
      it "returns success and updates access token" do
        old_access_token = account.access_token

        result = service.refresh_token!

        expect(result.success?).to be true
        expect(account.reload.access_token).not_to eq(old_access_token)
        expect(account.token_expires_at).to be_within(2.seconds).of(1.hour.from_now)
      end
    end

    context "when refresh token is missing" do
      before { account.update!(refresh_token_encrypted: nil) }

      it "returns failure" do
        result = service.refresh_token!

        expect(result.failure?).to be true
      end
    end
  end

  describe "#revoke!" do
    let(:account) { create(:connectors_account, :with_tokens, provider: "stub", user: user, organization: organization) }
    let(:service) { described_class.new(connector_account: account) }

    it "revokes the account and clears tokens" do
      result = service.revoke!

      expect(result.success?).to be true
      expect(account.reload.status).to eq("revoked")
      expect(account.access_token).to be_nil
      expect(account.refresh_token).to be_nil
    end
  end
end
