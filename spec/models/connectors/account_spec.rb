# == Schema Information
#
# Table name: connector_accounts
#
#  id                      :uuid             not null, primary key
#  access_token_encrypted  :text
#  display_name            :string
#  email                   :string
#  error_count             :integer          default(0), not null
#  last_error              :text
#  last_sync_at            :timestamptz
#  metadata                :jsonb            not null
#  provider                :string           not null
#  provider_uid            :string           not null
#  refresh_token_encrypted :text
#  status                  :string           default("active"), not null
#  token_expires_at        :timestamptz
#  token_scope             :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  organization_id         :uuid             not null
#  user_id                 :uuid             not null
#
# Indexes
#
#  idx_on_user_id_provider_provider_uid_1cce2a45f8  (user_id,provider,provider_uid) UNIQUE
#  index_connector_accounts_on_created_at           (created_at)
#  index_connector_accounts_on_organization_id      (organization_id)
#  index_connector_accounts_on_provider             (provider)
#  index_connector_accounts_on_status               (status)
#  index_connector_accounts_on_user_id              (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (user_id => users.id)
#
require "rails_helper"

RSpec.describe Connectors::Account, type: :model do
  subject(:account) { build(:connectors_account) }

  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:organization) }
    it { is_expected.to have_many(:settings).dependent(:destroy).with_foreign_key(:connector_account_id) }
    it { is_expected.to have_many(:sync_logs).dependent(:destroy).with_foreign_key(:connector_account_id) }
    it { is_expected.to have_many(:event_mappings).dependent(:destroy).with_foreign_key(:connector_account_id) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:user_id) }
    it { is_expected.to validate_presence_of(:organization_id) }
    it { is_expected.to validate_presence_of(:provider) }
    it { is_expected.to validate_presence_of(:provider_uid) }
  end

  describe "token storage" do
    it "stores access token encrypted" do
      account.save!
      expect(account.access_token_encrypted).to be_nil # no token set
    end

    it "stores refresh token encrypted" do
      account.save!
      expect(account.refresh_token_encrypted).to be_nil # no token set
    end

    it "returns nil for missing tokens" do
      account.access_token_encrypted = nil
      expect(account.access_token).to be_nil
    end
  end

  describe "#connected?" do
    it "returns true when active with access token" do
      account = create(:connectors_account, :with_tokens, status: "active")
      expect(account.connected?).to be true
    end

    it "returns false when paused" do
      account = create(:connectors_account, :paused)
      expect(account.connected?).to be false
    end
  end

  describe "#token_expired?" do
    it "returns true when token_expires_at is past" do
      account = create(:connectors_account, token_expires_at: 1.hour.ago)
      expect(account.token_expired?).to be true
    end

    it "returns false when token_expires_at is future" do
      account = create(:connectors_account, token_expires_at: 1.hour.from_now)
      expect(account.token_expired?).to be false
    end
  end

  describe "scopes" do
    let!(:google_account) { create(:connectors_account, provider: "google_calendar") }
    let!(:slack_account) { create(:connectors_account, provider: "slack") }

    describe ".by_provider" do
      it "filters by provider" do
        expect(Connectors::Account.by_provider("google_calendar")).to include(google_account)
        expect(Connectors::Account.by_provider("google_calendar")).not_to include(slack_account)
      end
    end

    describe ".active_only" do
      before do
        google_account.update!(status: "active")
        slack_account.update!(status: "paused")
      end

      it "returns only active accounts" do
        expect(Connectors::Account.active_only).to include(google_account)
        expect(Connectors::Account.active_only).not_to include(slack_account)
      end
    end
  end
end
