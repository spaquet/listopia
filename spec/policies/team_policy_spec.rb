# spec/policies/team_policy_spec.rb
require 'rails_helper'

RSpec.describe TeamPolicy, type: :policy do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:organization) { create(:organization, creator: user) }
  let(:team) { create(:team, organization: organization, created_by: user) }
  let(:policy) { described_class.new(user, team) }

  before do
    # Add user to organization
    create(:organization_membership, organization: organization, user: user, role: :admin)
    # Add other_user to organization
    create(:organization_membership, organization: organization, user: other_user, role: :member)
  end

  describe '#index?' do
    context 'when user is in the organization' do
      it { is_expected.to permit(:index) }
    end

    context 'when user is not in the organization' do
      let(:other_org) { create(:organization) }
      let(:other_team) { create(:team, organization: other_org) }
      let(:policy) { described_class.new(user, other_team) }

      it { is_expected.not_to permit(:index) }
    end
  end

  describe '#show?' do
    context 'when user is a team member' do
      before { create(:team_membership, team: team, user: user, organization_membership: organization.membership_for(user)) }

      it { is_expected.to permit(:show) }
    end

    context 'when user is not a team member' do
      it { is_expected.not_to permit(:show) }
    end
  end

  describe '#create?' do
    context 'when user is admin in organization' do
      it { is_expected.to permit(:create) }
    end

    context 'when user is member in organization' do
      let(:member_user) { create(:user) }
      let(:policy) { described_class.new(member_user, team) }

      before { create(:organization_membership, organization: organization, user: member_user, role: :member) }

      it { is_expected.not_to permit(:create) }
    end

    context 'when user is not in organization' do
      let(:outside_user) { create(:user) }
      let(:policy) { described_class.new(outside_user, team) }

      it { is_expected.not_to permit(:create) }
    end
  end

  describe '#update?' do
    context 'when user is team admin' do
      before { create(:team_membership, team: team, user: user, organization_membership: organization.membership_for(user), role: :admin) }

      it { is_expected.to permit(:update) }
    end

    context 'when user is team lead' do
      before { create(:team_membership, team: team, user: user, organization_membership: organization.membership_for(user), role: :lead) }

      it { is_expected.to permit(:update) }
    end

    context 'when user is team member' do
      before { create(:team_membership, team: team, user: user, organization_membership: organization.membership_for(user), role: :member) }

      it { is_expected.not_to permit(:update) }
    end

    context 'when user is not a team member' do
      it { is_expected.not_to permit(:update) }
    end
  end

  describe '#destroy?' do
    context 'when user is team admin' do
      before { create(:team_membership, team: team, user: user, organization_membership: organization.membership_for(user), role: :admin) }

      it { is_expected.to permit(:destroy) }
    end

    context 'when user is team member' do
      before { create(:team_membership, team: team, user: user, organization_membership: organization.membership_for(user), role: :member) }

      it { is_expected.not_to permit(:destroy) }
    end
  end

  describe '#manage_members?' do
    context 'when user is team admin' do
      before { create(:team_membership, team: team, user: user, organization_membership: organization.membership_for(user), role: :admin) }

      it { is_expected.to permit(:manage_members) }
    end

    context 'when user is team lead' do
      before { create(:team_membership, team: team, user: user, organization_membership: organization.membership_for(user), role: :lead) }

      it { is_expected.to permit(:manage_members) }
    end

    context 'when user is team member' do
      before { create(:team_membership, team: team, user: user, organization_membership: organization.membership_for(user), role: :member) }

      it { is_expected.not_to permit(:manage_members) }
    end
  end

  describe '#add_member?' do
    context 'when user is team admin' do
      before { create(:team_membership, team: team, user: user, organization_membership: organization.membership_for(user), role: :admin) }

      it { is_expected.to permit(:add_member) }
    end

    context 'when user is team member' do
      before { create(:team_membership, team: team, user: user, organization_membership: organization.membership_for(user), role: :member) }

      it { is_expected.not_to permit(:add_member) }
    end
  end

  describe '#update_member_role?' do
    context 'when user is team admin' do
      before { create(:team_membership, team: team, user: user, organization_membership: organization.membership_for(user), role: :admin) }

      it { is_expected.to permit(:update_member_role) }
    end

    context 'when user is team lead' do
      before { create(:team_membership, team: team, user: user, organization_membership: organization.membership_for(user), role: :lead) }

      it { is_expected.to permit(:update_member_role) }
    end

    context 'when user is team member' do
      before { create(:team_membership, team: team, user: user, organization_membership: organization.membership_for(user), role: :member) }

      it { is_expected.not_to permit(:update_member_role) }
    end
  end

  describe 'Scope' do
    let(:user_org) { create(:organization) }
    let(:user_team) { create(:team, organization: user_org) }
    let(:other_org) { create(:organization) }
    let(:other_team) { create(:team, organization: other_org) }

    before do
      create(:organization_membership, organization: user_org, user: user)
      create(:organization_membership, organization: other_org, user: other_user)
    end

    it 'includes teams in organizations the user is a member of' do
      expect(Pundit.policy_scope(user, Team)).to include(user_team)
    end

    it 'excludes teams in organizations the user is not a member of' do
      expect(Pundit.policy_scope(user, Team)).not_to include(other_team)
    end
  end
end
