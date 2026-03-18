RSpec.shared_examples "a connector" do
  let(:connector_class) { described_class }
  let(:user) { create(:user) }
  let(:organization) { create(:organization, created_by: user) }
  let(:account) do
    create(:connectors_account,
      user: user,
      organization: organization,
      provider: connector_class.key)
  end
  let(:connector) { connector_class.new(account) }

  describe "class methods" do
    it { expect(connector_class).to respond_to(:key) }
    it { expect(connector_class).to respond_to(:name) }
    it { expect(connector_class).to respond_to(:category) }
    it { expect(connector_class).to respond_to(:icon) }
    it { expect(connector_class).to respond_to(:description) }
    it { expect(connector_class).to respond_to(:oauth_required?) }
    it { expect(connector_class).to respond_to(:oauth_scopes_list) }
    it { expect(connector_class).to respond_to(:schema) }
  end

  describe "#connected?" do
    context "when account is active and has token" do
      before { account.update!(status: :active, access_token_encrypted: account.send(:encryptor).encrypt_and_sign("token")) }

      it { expect(connector.connected?).to be true }
    end

    context "when account is not active" do
      before { account.update!(status: :paused) }

      it { expect(connector.connected?).to be false }
    end

    context "when account has no token" do
      before { account.update!(access_token_encrypted: nil) }

      it { expect(connector.connected?).to be false }
    end
  end

  describe "#token_expired?" do
    context "when token_expires_at is in the past" do
      before { account.update!(token_expires_at: 1.hour.ago) }

      it { expect(connector.token_expired?).to be true }
    end

    context "when token_expires_at is in the future" do
      before { account.update!(token_expires_at: 1.hour.from_now) }

      it { expect(connector.token_expired?).to be false }
    end

    context "when token_expires_at is nil" do
      before { account.update!(token_expires_at: nil) }

      it { expect(connector.token_expired?).to be false }
    end
  end
end

RSpec.shared_examples "a connector service" do
  let(:service_class) { described_class }
  let(:user) { create(:user) }
  let(:organization) { create(:organization, created_by: user) }
  let(:account) { create(:connectors_account, user: user, organization: organization) }
  let(:service) { service_class.new(connector_account: account) }

  describe "initialization" do
    it { expect(service.connector_account).to eq(account) }
  end

  describe "#with_sync_log" do
    it "creates a sync log record" do
      expect {
        service.with_sync_log(operation: "test") { "result" }
      }.to change(account.sync_logs, :count).by(1)
    end

    it "marks sync log as success" do
      service.with_sync_log(operation: "test") { "result" }
      expect(account.sync_logs.last.status).to eq("success")
    end

    it "handles errors and marks sync log as failure" do
      expect {
        service.with_sync_log(operation: "test") do
          raise "Test error"
        end
      }.to raise_error("Test error")

      expect(account.sync_logs.last.status).to eq("failure")
    end
  end
end
