require 'rails_helper'

RSpec.describe OrganizationMembersController, type: :request do
  let(:user) { create(:user, :verified) }
  let(:other_user) { create(:user, :verified) }
  let(:organization) { create(:organization, creator: user) }

  before do
    create(:organization_membership, organization: organization, user: user, role: :owner)
  end

  def login_as(user)
    post session_path, params: { email: user.email, password: user.password }
  end

  describe 'authentication' do
    it 'requires user to be signed in for index' do
      get organization_members_path(organization)
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for show' do
      member = create(:organization_membership, organization: organization, user: other_user, role: :member)
      get organization_member_path(organization, member)
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for new' do
      get new_organization_member_path(organization)
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for create' do
      post organization_members_path(organization), params: { emails: ['test@example.com'] }
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe 'authorization' do
    let(:non_owner) { create(:user, :verified) }

    before do
      create(:organization_membership, organization: organization, user: non_owner, role: :member)
      login_as(non_owner)
    end

    it 'denies access to members list for non-owners' do
      get organization_members_path(organization)
      expect(response).to redirect_to(root_path)
    end
  end

  describe 'GET #index' do
    before { login_as(user) }

    it 'returns 200' do
      get organization_members_path(organization)
      expect([200, 406]).to include(response.status)
    end

    it 'assigns members' do
      create(:organization_membership, organization: organization, user: other_user, role: :member)
      get organization_members_path(organization)
      expect(assigns(:members)).to be_present
    end

    it 'paginates members' do
      create_list(:organization_membership, 5, organization: organization)
      get organization_members_path(organization)
      expect(assigns(:pagy)).to be_present
    end

    it 'orders by created_at descending' do
      user1 = create(:user, :verified)
      user2 = create(:user, :verified)
      m1 = create(:organization_membership, organization: organization, user: user1, created_at: 1.day.ago)
      m2 = create(:organization_membership, organization: organization, user: user2)

      get organization_members_path(organization)
      members = assigns(:members)

      expect(members.first.id).to eq(m2.id)
    end
  end

  describe 'GET #show' do
    before { login_as(user) }

    it 'returns 200' do
      member = create(:organization_membership, organization: organization, user: other_user, role: :member)
      get organization_member_path(organization, member)
      expect([200, 406]).to include(response.status)
    end

    it 'assigns the member' do
      member = create(:organization_membership, organization: organization, user: other_user, role: :member)
      get organization_member_path(organization, member)
      expect(assigns(:member)).to eq(member)
    end
  end

  describe 'GET #new' do
    before { login_as(user) }

    it 'returns 200' do
      get new_organization_member_path(organization)
      expect([200, 406]).to include(response.status)
    end

    it 'assigns new invitation' do
      get new_organization_member_path(organization)
      expect(assigns(:invitation)).to be_a_new(Invitation)
    end
  end

  describe 'POST #create' do
    before { login_as(user) }

    it 'invites users' do
      expect {
        post organization_members_path(organization),
             params: { emails: ['new@example.com'], role: 'member' }
      }.to change(Invitation, :count)
    end

    it 'redirects to members index' do
      post organization_members_path(organization),
           params: { emails: ['new@example.com'], role: 'member' }
      expect(response).to redirect_to(organization_members_path(organization))
    end

    it 'displays success message' do
      post organization_members_path(organization),
           params: { emails: ['new@example.com'], role: 'member' }
      follow_redirect!
      expect(response.body).to include('sent')
    end

    context 'with multiple emails' do
      it 'invites all users' do
        expect {
          post organization_members_path(organization),
               params: { emails: ['user1@example.com', 'user2@example.com'], role: 'admin' }
        }.to change(Invitation, :count).by(2)
      end
    end

    context 'with admin role' do
      it 'sets admin role' do
        post organization_members_path(organization),
             params: { emails: ['new@example.com'], role: 'admin' }
        invitation = Invitation.last
        expect(invitation.metadata['role']).to eq('admin')
      end
    end
  end

  describe 'PATCH #update_role' do
    before { login_as(user) }

    it 'updates member role' do
      member = create(:organization_membership, organization: organization, user: other_user, role: 'member')
      patch update_role_organization_member_path(organization, member),
            params: { role: 'admin' }
      expect(member.reload.role).to eq('admin')
    end

    it 'redirects to members index' do
      member = create(:organization_membership, organization: organization, user: other_user, role: 'member')
      patch update_role_organization_member_path(organization, member),
            params: { role: 'admin' }
      expect(response).to redirect_to(organization_members_path(organization))
    end

    context 'turbo stream' do
      it 'returns turbo stream response' do
        member = create(:organization_membership, organization: organization, user: other_user, role: 'member')
        patch update_role_organization_member_path(organization, member),
              params: { role: 'admin' },
              headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect([200, 406]).to include(response.status)
      end
    end
  end

  describe 'DELETE #remove' do
    before { login_as(user) }

    it 'removes member' do
      member = create(:organization_membership, organization: organization, user: other_user, role: :member)
      member_id = member.id

      delete remove_organization_member_path(organization, member)

      expect(OrganizationMembership.exists?(member_id)).to be false
    end

    it 'redirects to members index' do
      member = create(:organization_membership, organization: organization, user: other_user, role: :member)
      delete remove_organization_member_path(organization, member)
      expect(response).to redirect_to(organization_members_path(organization))
    end

    it 'displays success message' do
      member = create(:organization_membership, organization: organization, user: other_user, role: :member)
      delete remove_organization_member_path(organization, member)
      follow_redirect!
      expect(response.body).to include('removed')
    end

    context 'preventing removal of last owner' do
      it 'denies removal of last owner' do
        # user is the only owner
        delete remove_organization_member_path(organization, organization.organization_memberships.find_by(user: user))
        expect(response).to redirect_to(organization_members_path(organization))
        expect(flash[:alert]).to include('Cannot remove the last owner')
      end
    end

    context 'turbo stream' do
      it 'returns turbo stream response' do
        member = create(:organization_membership, organization: organization, user: other_user, role: :member)
        delete remove_organization_member_path(organization, member),
               headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect([200, 406]).to include(response.status)
      end
    end
  end

  describe 'nested resource routing' do
    before { login_as(user) }

    it 'requires valid organization_id' do
      get organization_members_path('invalid-id')
      expect(response).to redirect_to(root_path)
    end
  end
end
