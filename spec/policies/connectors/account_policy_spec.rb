require "rails_helper"

RSpec.describe Connectors::AccountPolicy, type: :policy do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:account) { create(:connectors_account, user: user) }
  let(:other_account) { create(:connectors_account, user: other_user) }

  describe "#index?" do
    it "allows authenticated users" do
      policy = described_class.new(user, Connectors::Account)
      expect(policy.index?).to be_truthy
    end

    it "denies unauthenticated users" do
      policy = described_class.new(nil, Connectors::Account)
      expect(policy.index?).to be_falsy
    end
  end

  describe "#show?" do
    it "allows user to view own account" do
      policy = described_class.new(user, account)
      expect(policy.show?).to be_truthy
    end

    it "denies user from viewing other's account" do
      policy = described_class.new(other_user, account)
      expect(policy.show?).to be_falsy
    end
  end

  describe "#create?" do
    it "allows authenticated users" do
      policy = described_class.new(user, Connectors::Account.new)
      expect(policy.create?).to be_truthy
    end

    it "denies unauthenticated users" do
      policy = described_class.new(nil, Connectors::Account.new)
      expect(policy.create?).to be_falsy
    end
  end

  describe "#update?" do
    it "allows user to update own account" do
      policy = described_class.new(user, account)
      expect(policy.update?).to be_truthy
    end

    it "denies user from updating other's account" do
      policy = described_class.new(other_user, account)
      expect(policy.update?).to be_falsy
    end
  end

  describe "#destroy?" do
    it "allows user to destroy own account" do
      policy = described_class.new(user, account)
      expect(policy.destroy?).to be_truthy
    end

    it "denies user from destroying other's account" do
      policy = described_class.new(other_user, account)
      expect(policy.destroy?).to be_falsy
    end
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
