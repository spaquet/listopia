# spec/policies/team_policy_spec.rb
require 'rails_helper'

RSpec.describe TeamPolicy, type: :policy do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:organization) { create(:organization, creator: user) }
  let(:team) { create(:team, organization: organization, creator: user) }
  let(:policy) { described_class.new(user, team) }

  before do
    # Add user to organization (organization factory creates membership for creator)
    # Add other_user to organization
    create(:organization_membership, organization: organization, user: other_user, role: :member)
  end

  describe '#index?' do
    context 'when user is in the organization' do
      it 'allows user in organization' do
        expect(policy.index?).to be_truthy
      end
    end

    context 'when user is not in the organization' do
      let(:other_user_not_in_org) { create(:user) }
      let(:other_org) { create(:organization) }
      let(:other_team) { create(:team, organization: other_org) }
      let(:policy) { described_class.new(other_user_not_in_org, other_team) }

      it 'denies user not in organization' do
        expect(policy.index?).to be_falsy
      end
    end
  end

  describe '#show?' do
    context 'when user is a team member' do
      it 'allows team members to view' do
        expect(policy.show?).to be_truthy
      end
    end

    context 'when user is not a team member' do
      let(:policy) { described_class.new(other_user, team) }

      it 'denies non-team members' do
        expect(policy.show?).to be_falsy
      end
    end
  end

  describe '#create?' do
    context 'when user is admin in organization' do
      it 'allows admin to create' do
        expect(policy.create?).to be_truthy
      end
    end

    context 'when user is member in organization' do
      let(:member_user) { create(:user) }
      let(:policy) { described_class.new(member_user, team) }

      before { create(:organization_membership, organization: organization, user: member_user, role: :member) }

      it 'denies member from creating' do
        expect(policy.create?).to be_falsy
      end
    end

    context 'when user is not in organization' do
      let(:outside_user) { create(:user) }
      let(:policy) { described_class.new(outside_user, team) }

      it 'denies outside user from creating' do
        expect(policy.create?).to be_falsy
      end
    end
  end

  describe '#update?' do
    context 'when user is team admin' do
      it 'allows admin to update' do
        expect(policy.update?).to be_truthy
      end
    end

    context 'when user is team lead' do
      let(:lead_user) { create(:user) }
      let(:lead_membership) { create(:organization_membership, organization: organization, user: lead_user, role: :member) }
      let(:policy) { described_class.new(lead_user, team) }

      before { create(:team_membership, team: team, user: lead_user, organization_membership: lead_membership, role: :lead) }

      it 'allows lead to update' do
        expect(policy.update?).to be_truthy
      end
    end

    context 'when user is team member' do
      let(:member_user) { create(:user) }
      let(:member_org_membership) { create(:organization_membership, organization: organization, user: member_user, role: :member) }
      let(:policy) { described_class.new(member_user, team) }

      before { create(:team_membership, team: team, user: member_user, organization_membership: member_org_membership, role: :member) }

      it 'denies member from updating' do
        expect(policy.update?).to be_falsy
      end
    end

    context 'when user is not a team member' do
      let(:policy) { described_class.new(other_user, team) }

      it 'denies non-team member' do
        expect(policy.update?).to be_falsy
      end
    end
  end

  describe '#destroy?' do
    context 'when user is team admin' do
      it 'allows admin to destroy' do
        expect(policy.destroy?).to be_truthy
      end
    end

    context 'when user is team member' do
      let(:member_user) { create(:user) }
      let(:member_org_membership) { create(:organization_membership, organization: organization, user: member_user, role: :member) }
      let(:policy) { described_class.new(member_user, team) }

      before { create(:team_membership, team: team, user: member_user, organization_membership: member_org_membership, role: :member) }

      it 'denies member from destroying' do
        expect(policy.destroy?).to be_falsy
      end
    end
  end

  describe '#manage_members?' do
    context 'when user is team admin' do
      it 'allows admin to manage members' do
        expect(policy.manage_members?).to be_truthy
      end
    end

    context 'when user is team lead' do
      let(:lead_user) { create(:user) }
      let(:lead_membership) { create(:organization_membership, organization: organization, user: lead_user, role: :member) }
      let(:policy) { described_class.new(lead_user, team) }

      before { create(:team_membership, team: team, user: lead_user, organization_membership: lead_membership, role: :lead) }

      it 'allows lead to manage members' do
        expect(policy.manage_members?).to be_truthy
      end
    end

    context 'when user is team member' do
      let(:member_user) { create(:user) }
      let(:member_org_membership) { create(:organization_membership, organization: organization, user: member_user, role: :member) }
      let(:policy) { described_class.new(member_user, team) }

      before { create(:team_membership, team: team, user: member_user, organization_membership: member_org_membership, role: :member) }

      it 'denies member from managing members' do
        expect(policy.manage_members?).to be_falsy
      end
    end
  end

  describe '#add_member?' do
    context 'when user is team admin' do
      it 'allows admin to add member' do
        expect(policy.add_member?).to be_truthy
      end
    end

    context 'when user is team member' do
      let(:member_user) { create(:user) }
      let(:member_org_membership) { create(:organization_membership, organization: organization, user: member_user, role: :member) }
      let(:policy) { described_class.new(member_user, team) }

      before { create(:team_membership, team: team, user: member_user, organization_membership: member_org_membership, role: :member) }

      it 'denies member from adding member' do
        expect(policy.add_member?).to be_falsy
      end
    end
  end

  describe '#update_member_role?' do
    context 'when user is team admin' do
      it 'allows admin to update member role' do
        expect(policy.update_member_role?).to be_truthy
      end
    end

    context 'when user is team lead' do
      let(:lead_user) { create(:user) }
      let(:lead_membership) { create(:organization_membership, organization: organization, user: lead_user, role: :member) }
      let(:policy) { described_class.new(lead_user, team) }

      before { create(:team_membership, team: team, user: lead_user, organization_membership: lead_membership, role: :lead) }

      it 'allows lead to update member role' do
        expect(policy.update_member_role?).to be_truthy
      end
    end

    context 'when user is team member' do
      let(:member_user) { create(:user) }
      let(:member_org_membership) { create(:organization_membership, organization: organization, user: member_user, role: :member) }
      let(:policy) { described_class.new(member_user, team) }

      before { create(:team_membership, team: team, user: member_user, organization_membership: member_org_membership, role: :member) }

      it 'denies member from updating member role' do
        expect(policy.update_member_role?).to be_falsy
      end
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
