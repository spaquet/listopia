require "rails_helper"

RSpec.describe Connectors::OauthService, type: :service do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, creator: user) }

  describe "#revoke!" do
    let(:account) { create(:connectors_account, :with_tokens, user: user, organization: organization) }
    let(:service) { described_class.new(connector_account: account) }

    it "revokes the account and clears tokens" do
      result = service.revoke!

      expect(result.success?).to be true
      expect(account.reload.status).to eq("revoked")
      expect(account.access_token).to be_nil
      expect(account.refresh_token).to be_nil
    end
  end

  describe "#save_tokens!" do
    let(:account) { create(:connectors_account, user: user, organization: organization) }
    let(:service) { described_class.new(connector_account: account) }

    it "saves access token and refresh token with expiration" do
      service.send(:save_tokens!,
        access_token: "new_access_token",
        refresh_token: "new_refresh_token",
        expires_in: 3600
      )

      account.reload
      expect(account.access_token).to eq("new_access_token")
      expect(account.refresh_token).to eq("new_refresh_token")
      expect(account.token_expires_at).to be_within(2.seconds).of(1.hour.from_now)
      expect(account.status).to eq("active")
    end

    it "updates sync timestamp and clears errors" do
      account.update!(error_count: 5, last_error: "Previous error")

      service.send(:save_tokens!,
        access_token: "token",
        expires_in: 3600
      )

      account.reload
      expect(account.error_count).to eq(0)
      expect(account.last_error).to be_nil
      expect(account.last_sync_at).to be_within(2.seconds).of(Time.current)
    end
  end
end
