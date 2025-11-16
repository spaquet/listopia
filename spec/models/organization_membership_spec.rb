# spec/models/organization_membership_spec.rb
require 'rails_helper'

RSpec.describe OrganizationMembership, type: :model do
  let(:organization) { create(:organization) }
  let(:user) { create(:user) }
  let(:membership) { create(:organization_membership, organization: organization, user: user) }

  describe 'associations' do
    it { is_expected.to belong_to(:organization) }
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:team_memberships).dependent(:destroy) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:user_id) }
    it { is_expected.to validate_presence_of(:organization_id) }
    it { is_expected.to validate_presence_of(:role) }
    it { is_expected.to validate_presence_of(:status) }

    it 'validates uniqueness of user per organization' do
      create(:organization_membership, organization: organization, user: user)
      duplicate = build(:organization_membership, organization: organization, user: user)
      expect(duplicate).not_to be_valid
    end

    it 'validates role inclusion' do
      membership = build(:organization_membership, role: 'invalid_role')
      expect(membership).not_to be_valid
    end

    it 'validates status inclusion' do
      membership = build(:organization_membership, status: 'invalid_status')
      expect(membership).not_to be_valid
    end
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:role).with_values(member: 0, admin: 1, owner: 2) }
    it { is_expected.to define_enum_for(:status).with_values(pending: 0, active: 1, suspended: 2, revoked: 3) }
  end

  describe 'callbacks' do
    it 'sets default status to active' do
      membership = create(:organization_membership, status: nil)
      expect(membership.status).to eq('active')
    end

    it 'sets default role to member' do
      membership = create(:organization_membership, role: nil)
      expect(membership.role).to eq('member')
    end

    it 'sets joined_at on creation' do
      membership = create(:organization_membership, joined_at: nil)
      expect(membership.joined_at).not_to be nil
    end
  end

  describe '#activate!' do
    it 'changes status to active' do
      membership = create(:organization_membership, status: :pending)
      membership.activate!
      expect(membership.status).to eq('active')
    end
  end

  describe '#suspend!' do
    it 'changes status to suspended' do
      membership.suspend!
      expect(membership.status).to eq('suspended')
    end
  end

  describe '#revoke!' do
    it 'changes status to revoked' do
      membership.revoke!
      expect(membership.status).to eq('revoked')
    end
  end

  describe '#can_manage_organization?' do
    it 'returns true for admin role' do
      membership = create(:organization_membership, role: :admin)
      expect(membership.can_manage_organization?).to be true
    end

    it 'returns true for owner role' do
      membership = create(:organization_membership, role: :owner)
      expect(membership.can_manage_organization?).to be true
    end

    it 'returns false for member role' do
      membership = create(:organization_membership, role: :member)
      expect(membership.can_manage_organization?).to be false
    end
  end

  describe '#can_manage_teams?' do
    it 'returns true for admin role' do
      membership = create(:organization_membership, role: :admin)
      expect(membership.can_manage_teams?).to be true
    end

    it 'returns false for member role' do
      membership = create(:organization_membership, role: :member)
      expect(membership.can_manage_teams?).to be false
    end
  end

  describe '#can_manage_members?' do
    it 'returns true for owner role' do
      membership = create(:organization_membership, role: :owner)
      expect(membership.can_manage_members?).to be true
    end

    it 'returns false for member role' do
      membership = create(:organization_membership, role: :member)
      expect(membership.can_manage_members?).to be false
    end
  end

  describe 'scopes' do
    describe '.active' do
      it 'returns only active memberships' do
        active = create(:organization_membership, status: :active)
        suspended = create(:organization_membership, status: :suspended)
        expect(OrganizationMembership.active).to include(active)
        expect(OrganizationMembership.active).not_to include(suspended)
      end
    end

    describe '.by_role' do
      it 'filters by role' do
        admin = create(:organization_membership, role: :admin)
        member = create(:organization_membership, role: :member)
        expect(OrganizationMembership.by_role('admin')).to include(admin)
        expect(OrganizationMembership.by_role('admin')).not_to include(member)
      end
    end

    describe '.admins_and_owners' do
      it 'returns only admins and owners' do
        admin = create(:organization_membership, role: :admin)
        owner = create(:organization_membership, role: :owner)
        member = create(:organization_membership, role: :member)
        result = OrganizationMembership.admins_and_owners
        expect(result).to include(admin, owner)
        expect(result).not_to include(member)
      end
    end
  end
end
