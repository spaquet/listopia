require "rails_helper"

RSpec.describe Connectors::AccountPolicy, type: :policy do
  subject { described_class }

  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:account) { create(:connectors_account, user: user) }
  let(:other_account) { create(:connectors_account, user: other_user) }

  permissions :index? do
    it { is_expected.to permit(user) }
    it { is_expected.not_to permit(nil) }
  end

  permissions :show? do
    it { is_expected.to permit(user, account) }
    it { is_expected.not_to permit(other_user, account) }
  end

  permissions :create? do
    it { is_expected.to permit(user) }
    it { is_expected.not_to permit(nil) }
  end

  permissions :update? do
    it { is_expected.to permit(user, account) }
    it { is_expected.not_to permit(other_user, account) }
  end

  permissions :destroy? do
    it { is_expected.to permit(user, account) }
    it { is_expected.not_to permit(other_user, account) }
  end

  describe "Scope" do
    let!(:user_account) { create(:connectors_account, user: user) }
    let!(:other_account) { create(:connectors_account, user: other_user) }

    it "returns only user's accounts" do
      scope = Pundit.policy_scope!(user, Connectors::Account)
      expect(scope).to include(user_account)
      expect(scope).not_to include(other_account)
    end
  end
end
