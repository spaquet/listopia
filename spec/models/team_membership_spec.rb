# spec/models/team_membership_spec.rb
require 'rails_helper'

RSpec.describe TeamMembership, type: :model do
  let(:organization) { create(:organization) }
  let(:user) { create(:user) }
  let(:org_membership) { create(:organization_membership, organization: organization, user: user) }
  let(:team) { create(:team, organization: organization) }
  let(:team_membership) { create(:team_membership, team: team, user: user, organization_membership: org_membership) }

  describe 'associations' do
    it { is_expected.to belong_to(:team) }
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:organization_membership) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:user_id) }
    it { is_expected.to validate_presence_of(:team_id) }
    it { is_expected.to validate_presence_of(:organization_membership_id) }
    it { is_expected.to validate_presence_of(:role) }
    it { is_expected.to validate_presence_of(:joined_at) }

    it 'validates uniqueness of user per team' do
      create(:team_membership, team: team, user: user, organization_membership: org_membership)
      duplicate = build(:team_membership, team: team, user: user, organization_membership: org_membership)
      expect(duplicate).not_to be_valid
    end

    it 'validates role inclusion' do
      membership = build(:team_membership, role: 'invalid_role')
      expect(membership).not_to be_valid
    end

    it 'validates user must be org member' do
      other_user = create(:user)
      membership = build(:team_membership, user: other_user, team: team)
      expect(membership).not_to be_valid
      expect(membership.errors[:user]).to be_present
    end
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:role).with_values(member: 0, lead: 1, admin: 2) }
  end

  describe 'callbacks' do
    it 'sets default role to member' do
      membership = create(:team_membership, team: team, user: user, organization_membership: org_membership, role: nil)
      expect(membership.role).to eq('member')
    end

    it 'sets joined_at on creation' do
      membership = create(:team_membership, team: team, user: user, organization_membership: org_membership, joined_at: nil)
      expect(membership.joined_at).not_to be nil
    end

    it 'sets organization_membership from team' do
      new_membership = build(:team_membership, team: team, user: user, organization_membership: nil)
      new_membership.validate
      expect(new_membership.organization_membership).to eq(team.organization.membership_for(user))
    end
  end

  describe '#can_manage_team?' do
    it 'returns true for admin role' do
      membership = create(:team_membership, team: team, user: user, organization_membership: org_membership, role: :admin)
      expect(membership.can_manage_team?).to be true
    end

    it 'returns true for lead role' do
      membership = create(:team_membership, team: team, user: user, organization_membership: org_membership, role: :lead)
      expect(membership.can_manage_team?).to be true
    end

    it 'returns false for member role' do
      membership = create(:team_membership, team: team, user: user, organization_membership: org_membership, role: :member)
      expect(membership.can_manage_team?).to be false
    end
  end

  describe 'scopes' do
    describe '.by_role' do
      it 'filters by role' do
        admin = create(:team_membership, team: team, organization_membership: org_membership, role: :admin)
        member = create(:team_membership, team: team, organization_membership: create(:organization_membership, organization: organization, user: create(:user)), role: :member)
        expect(TeamMembership.by_role('admin')).to include(admin)
        expect(TeamMembership.by_role('admin')).not_to include(member)
      end
    end

    describe '.admins_and_leads' do
      it 'returns only admins and leads' do
        admin = create(:team_membership, team: team, organization_membership: org_membership, role: :admin)
        lead = create(:team_membership, team: team, organization_membership: create(:organization_membership, organization: organization, user: create(:user)), role: :lead)
        member = create(:team_membership, team: team, organization_membership: create(:organization_membership, organization: organization, user: create(:user)), role: :member)
        result = TeamMembership.admins_and_leads
        expect(result).to include(admin, lead)
        expect(result).not_to include(member)
      end
    end
  end
end
