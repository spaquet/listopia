# spec/policies/organization_policy_spec.rb
require 'rails_helper'

RSpec.describe OrganizationPolicy, type: :policy do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:organization) { create(:organization, creator: user) }
  let(:policy) { described_class.new(user, organization) }

  describe '#index?' do
    it 'allows authenticated users to see their organizations' do
      expect(policy.index?).to be_truthy
    end
  end

  describe '#show?' do
    context 'when user is a member' do
      before { create(:organization_membership, organization: organization, user: user) }

      it 'allows member to view' do
        expect(policy.show?).to be_truthy
      end
    end

    context 'when user is not a member' do
      it 'denies non-member from viewing' do
        expect(policy.show?).to be_falsy
      end
    end
  end

  describe '#create?' do
    it 'allows authenticated users to create organizations' do
      expect(policy.create?).to be_truthy
    end
  end

  describe '#update?' do
    context 'when user is admin' do
      before { create(:organization_membership, organization: organization, user: user, role: :admin) }

      it 'allows admin to update' do
        expect(policy.update?).to be_truthy
      end
    end

    context 'when user is owner' do
      before { create(:organization_membership, organization: organization, user: user, role: :owner) }

      it 'allows owner to update' do
        expect(policy.update?).to be_truthy
      end
    end

    context 'when user is member' do
      before { create(:organization_membership, organization: organization, user: user, role: :member) }

      it 'denies member from updating' do
        expect(policy.update?).to be_falsy
      end
    end

    context 'when user is not a member' do
      it 'denies non-member from updating' do
        expect(policy.update?).to be_falsy
      end
    end
  end

  describe '#destroy?' do
    context 'when user is owner' do
      before { create(:organization_membership, organization: organization, user: user, role: :owner) }

      it 'allows owner to destroy' do
        expect(policy.destroy?).to be_truthy
      end
    end

    context 'when user is admin' do
      before { create(:organization_membership, organization: organization, user: user, role: :admin) }

      it 'denies admin from destroying' do
        expect(policy.destroy?).to be_falsy
      end
    end

    context 'when user is member' do
      before { create(:organization_membership, organization: organization, user: user, role: :member) }

      it 'denies member from destroying' do
        expect(policy.destroy?).to be_falsy
      end
    end
  end

  describe '#manage_members?' do
    context 'when user is admin' do
      before { create(:organization_membership, organization: organization, user: user, role: :admin) }

      it 'allows admin to manage members' do
        expect(policy.manage_members?).to be_truthy
      end
    end

    context 'when user is owner' do
      before { create(:organization_membership, organization: organization, user: user, role: :owner) }

      it 'allows owner to manage members' do
        expect(policy.manage_members?).to be_truthy
      end
    end

    context 'when user is member' do
      before { create(:organization_membership, organization: organization, user: user, role: :member) }

      it 'denies member from managing members' do
        expect(policy.manage_members?).to be_falsy
      end
    end
  end

  describe '#invite_member?' do
    context 'when user is admin' do
      before { create(:organization_membership, organization: organization, user: user, role: :admin) }

      it 'allows admin to invite member' do
        expect(policy.invite_member?).to be_truthy
      end
    end

    context 'when user is member' do
      before { create(:organization_membership, organization: organization, user: user, role: :member) }

      it 'denies member from inviting' do
        expect(policy.invite_member?).to be_falsy
      end
    end
  end

  describe '#remove_member?' do
    context 'when user is admin' do
      before { create(:organization_membership, organization: organization, user: user, role: :admin) }

      it 'allows admin to remove member' do
        expect(policy.remove_member?).to be_truthy
      end
    end

    context 'when user is member' do
      before { create(:organization_membership, organization: organization, user: user, role: :member) }

      it 'denies member from removing' do
        expect(policy.remove_member?).to be_falsy
      end
    end
  end

  describe '#update_member_role?' do
    context 'when user is owner' do
      before { create(:organization_membership, organization: organization, user: user, role: :owner) }

      it 'allows owner to update member role' do
        expect(policy.update_member_role?).to be_truthy
      end
    end

    context 'when user is admin' do
      before { create(:organization_membership, organization: organization, user: user, role: :admin) }

      it 'allows admin to update member role' do
        expect(policy.update_member_role?).to be_truthy
      end
    end

    context 'when user is member' do
      before { create(:organization_membership, organization: organization, user: user, role: :member) }

      it 'denies member from updating role' do
        expect(policy.update_member_role?).to be_falsy
      end
    end
  end

  describe '#manage_teams?' do
    context 'when user is admin' do
      before { create(:organization_membership, organization: organization, user: user, role: :admin) }

      it 'allows admin to manage teams' do
        expect(policy.manage_teams?).to be_truthy
      end
    end

    context 'when user is member' do
      before { create(:organization_membership, organization: organization, user: user, role: :member) }

      it 'denies member from managing teams' do
        expect(policy.manage_teams?).to be_falsy
      end
    end
  end

  describe '#view_audit_logs?' do
    context 'when user is admin' do
      before { create(:organization_membership, organization: organization, user: user, role: :admin) }

      it 'allows admin to view audit logs' do
        expect(policy.view_audit_logs?).to be_truthy
      end
    end

    context 'when user is member' do
      before { create(:organization_membership, organization: organization, user: user, role: :member) }

      it 'denies member from viewing audit logs' do
        expect(policy.view_audit_logs?).to be_falsy
      end
    end
  end

  describe 'Scope' do
    let(:user_org) { create(:organization, creator: user) }
    let(:other_org) { create(:organization, creator: other_user) }

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
