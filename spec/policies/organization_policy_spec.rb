# spec/policies/organization_policy_spec.rb
require 'rails_helper'

RSpec.describe OrganizationPolicy, type: :policy do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:organization) { create(:organization, created_by: user) }
  let(:policy) { described_class.new(user, organization) }

  describe '#index?' do
    it 'allows authenticated users to see their organizations' do
      expect(policy).to permit(:index)
    end
  end

  describe '#show?' do
    context 'when user is a member' do
      before { create(:organization_membership, organization: organization, user: user) }

      it { is_expected.to permit(:show) }
    end

    context 'when user is not a member' do
      it { is_expected.not_to permit(:show) }
    end
  end

  describe '#create?' do
    it 'allows authenticated users to create organizations' do
      expect(policy).to permit(:create)
    end
  end

  describe '#update?' do
    context 'when user is admin' do
      before { create(:organization_membership, organization: organization, user: user, role: :admin) }

      it { is_expected.to permit(:update) }
    end

    context 'when user is owner' do
      before { create(:organization_membership, organization: organization, user: user, role: :owner) }

      it { is_expected.to permit(:update) }
    end

    context 'when user is member' do
      before { create(:organization_membership, organization: organization, user: user, role: :member) }

      it { is_expected.not_to permit(:update) }
    end

    context 'when user is not a member' do
      it { is_expected.not_to permit(:update) }
    end
  end

  describe '#destroy?' do
    context 'when user is owner' do
      before { create(:organization_membership, organization: organization, user: user, role: :owner) }

      it { is_expected.to permit(:destroy) }
    end

    context 'when user is admin' do
      before { create(:organization_membership, organization: organization, user: user, role: :admin) }

      it { is_expected.not_to permit(:destroy) }
    end

    context 'when user is member' do
      before { create(:organization_membership, organization: organization, user: user, role: :member) }

      it { is_expected.not_to permit(:destroy) }
    end
  end

  describe '#manage_members?' do
    context 'when user is admin' do
      before { create(:organization_membership, organization: organization, user: user, role: :admin) }

      it { is_expected.to permit(:manage_members) }
    end

    context 'when user is owner' do
      before { create(:organization_membership, organization: organization, user: user, role: :owner) }

      it { is_expected.to permit(:manage_members) }
    end

    context 'when user is member' do
      before { create(:organization_membership, organization: organization, user: user, role: :member) }

      it { is_expected.not_to permit(:manage_members) }
    end
  end

  describe '#invite_member?' do
    context 'when user is admin' do
      before { create(:organization_membership, organization: organization, user: user, role: :admin) }

      it { is_expected.to permit(:invite_member) }
    end

    context 'when user is member' do
      before { create(:organization_membership, organization: organization, user: user, role: :member) }

      it { is_expected.not_to permit(:invite_member) }
    end
  end

  describe '#remove_member?' do
    context 'when user is admin' do
      before { create(:organization_membership, organization: organization, user: user, role: :admin) }

      it { is_expected.to permit(:remove_member) }
    end

    context 'when user is member' do
      before { create(:organization_membership, organization: organization, user: user, role: :member) }

      it { is_expected.not_to permit(:remove_member) }
    end
  end

  describe '#update_member_role?' do
    context 'when user is owner' do
      before { create(:organization_membership, organization: organization, user: user, role: :owner) }

      it { is_expected.to permit(:update_member_role) }
    end

    context 'when user is admin' do
      before { create(:organization_membership, organization: organization, user: user, role: :admin) }

      it { is_expected.to permit(:update_member_role) }
    end

    context 'when user is member' do
      before { create(:organization_membership, organization: organization, user: user, role: :member) }

      it { is_expected.not_to permit(:update_member_role) }
    end
  end

  describe '#manage_teams?' do
    context 'when user is admin' do
      before { create(:organization_membership, organization: organization, user: user, role: :admin) }

      it { is_expected.to permit(:manage_teams) }
    end

    context 'when user is member' do
      before { create(:organization_membership, organization: organization, user: user, role: :member) }

      it { is_expected.not_to permit(:manage_teams) }
    end
  end

  describe '#view_audit_logs?' do
    context 'when user is admin' do
      before { create(:organization_membership, organization: organization, user: user, role: :admin) }

      it { is_expected.to permit(:view_audit_logs) }
    end

    context 'when user is member' do
      before { create(:organization_membership, organization: organization, user: user, role: :member) }

      it { is_expected.not_to permit(:view_audit_logs) }
    end
  end

  describe 'Scope' do
    let(:user_org) { create(:organization, created_by: user) }
    let(:other_org) { create(:organization, created_by: other_user) }

    before do
      create(:organization_membership, organization: user_org, user: user)
      create(:organization_membership, organization: other_org, user: other_user)
    end

    it 'includes organizations the user is a member of' do
      expect(Pundit.policy_scope(user, Organization)).to include(user_org)
    end

    it 'excludes organizations the user is not a member of' do
      expect(Pundit.policy_scope(user, Organization)).not_to include(other_org)
    end
  end
end
