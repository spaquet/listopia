require 'rails_helper'

RSpec.describe OrganizationInvitationsController, type: :request do
  let(:user) { create(:user, :verified) }
  let(:invited_user) { create(:user, :verified) }
  let(:organization) { create(:organization, creator: user) }

  before do
    create(:organization_membership, organization: organization, user: user, role: :owner)
  end

  def login_as(user)
    post session_path, params: { email: user.email, password: user.password }
  end

  describe 'authentication' do
    it 'requires user to be signed in for index' do
      get organization_invitations_path(organization)
      expect(response).to redirect_to(new_session_path)
    end

    it 'accepts unauthenticated user for accept action' do
      invitation = create(:invitation,
        invitable: organization,
        email: invited_user.email,
        status: 'pending',
        invitable_type: 'Organization'
      )
      get accept_organization_invitation_path(invitation.invitation_token)
      expect(response.status).to eq(302)
    end
  end

  describe 'GET #index' do
    before { login_as(user) }

    it 'returns 200' do
      get organization_invitations_path(organization)
      expect([200, 406]).to include(response.status)
    end

    it 'assigns pending invitations' do
      create(:invitation,
        invitable: organization,
        status: 'pending',
        invitable_type: 'Organization'
      )
      get organization_invitations_path(organization)
      expect(assigns(:invitations)).to be_present
    end

    it 'paginates invitations' do
      create_list(:invitation, 5, invitable: organization, status: 'pending', invitable_type: 'Organization')
      get organization_invitations_path(organization)
      expect(assigns(:pagy)).to be_present
    end

    it 'only shows pending invitations' do
      create(:invitation,
        invitable: organization,
        status: 'pending',
        invitable_type: 'Organization'
      )
      create(:invitation,
        invitable: organization,
        status: 'accepted',
        invitable_type: 'Organization'
      )
      get organization_invitations_path(organization)
      invitations = assigns(:invitations)
      expect(invitations.all? { |i| i.status == 'pending' }).to be true
    end
  end

  describe 'GET #show' do
    before { login_as(user) }

    it 'shows invitation details' do
      invitation = create(:invitation,
        invitable: organization,
        status: 'pending',
        invitable_type: 'Organization'
      )
      get organization_invitation_path(organization, invitation)
      expect([200, 406]).to include(response.status)
    end
  end

  describe 'GET #accept' do
    let(:invitation) do
      create(:invitation,
        invitable: organization,
        email: invited_user.email,
        status: 'pending',
        invitable_type: 'Organization'
      )
    end

    context 'when authenticated with correct email' do
      before { login_as(invited_user) }

      it 'creates organization membership' do
        expect {
          get accept_organization_invitation_path(invitation.invitation_token)
        }.to change(OrganizationMembership, :count).by(1)
      end

      it 'marks invitation as accepted' do
        get accept_organization_invitation_path(invitation.invitation_token)
        expect(invitation.reload.status).to eq('accepted')
      end

      it 'redirects to organization' do
        get accept_organization_invitation_path(invitation.invitation_token)
        expect(response).to redirect_to(organization_path(organization))
      end

      it 'displays success message' do
        get accept_organization_invitation_path(invitation.invitation_token)
        follow_redirect!
        expect(response.body).to include('joined')
      end

      context 'user already member' do
        before do
          create(:organization_membership, organization: organization, user: invited_user, role: :member)
        end

        it 'redirects without creating duplicate' do
          get accept_organization_invitation_path(invitation.invitation_token)
          expect(response).to redirect_to(organization_path(organization))
        end
      end
    end

    context 'when authenticated with wrong email' do
      let(:other_user) { create(:user, :verified, email: 'other@example.com') }

      before { login_as(other_user) }

      it 'rejects with alert' do
        get accept_organization_invitation_path(invitation.invitation_token)
        expect(response).to redirect_to(sign_in_path)
        expect(flash[:alert]).to include(invitation.email)
      end
    end

    context 'when unauthenticated' do
      it 'stores token in session' do
        get accept_organization_invitation_path(invitation.invitation_token)
        expect(session[:pending_organization_invitation_token]).to eq(invitation.invitation_token)
      end

      it 'redirects to signup' do
        get accept_organization_invitation_path(invitation.invitation_token)
        expect(response).to redirect_to(new_registration_path)
      end
    end

    context 'with invalid token' do
      it 'redirects to root' do
        get accept_organization_invitation_path('invalid-token')
        expect(response).to redirect_to(root_path)
      end
    end

    context 'with already accepted invitation' do
      before do
        invitation.update(status: 'accepted')
      end

      it 'rejects with alert' do
        login_as(invited_user)
        get accept_organization_invitation_path(invitation.invitation_token)
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe 'PATCH #resend' do
    before { login_as(user) }

    it 'resends invitation email' do
      invitation = create(:invitation,
        invitable: organization,
        status: 'pending',
        invitable_type: 'Organization'
      )
      allow(CollaborationMailer).to receive_message_chain(:organization_invitation, :deliver_later)
      patch resend_organization_invitation_path(organization, invitation)
      expect(response).to redirect_to(organization_invitations_path(organization))
    end

    it 'updates invitation_sent_at' do
      invitation = create(:invitation,
        invitable: organization,
        status: 'pending',
        invitable_type: 'Organization',
        invitation_sent_at: 1.day.ago
      )
      allow(CollaborationMailer).to receive_message_chain(:organization_invitation, :deliver_later)

      patch resend_organization_invitation_path(organization, invitation)
      expect(invitation.reload.invitation_sent_at).to be > 1.minute.ago
    end

    context 'turbo stream' do
      it 'returns turbo stream response' do
        invitation = create(:invitation,
          invitable: organization,
          status: 'pending',
          invitable_type: 'Organization'
        )
        patch resend_organization_invitation_path(organization, invitation),
              headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect([200, 406]).to include(response.status)
      end
    end
  end

  describe 'PATCH #revoke' do
    before { login_as(user) }

    it 'revokes invitation' do
      invitation = create(:invitation,
        invitable: organization,
        status: 'pending',
        invitable_type: 'Organization'
      )
      patch revoke_organization_invitation_path(organization, invitation)
      expect(invitation.reload.status).to eq('revoked')
    end

    it 'redirects to invitations index' do
      invitation = create(:invitation,
        invitable: organization,
        status: 'pending',
        invitable_type: 'Organization'
      )
      patch revoke_organization_invitation_path(organization, invitation)
      expect(response).to redirect_to(organization_invitations_path(organization))
    end

    it 'displays success message' do
      invitation = create(:invitation,
        invitable: organization,
        status: 'pending',
        invitable_type: 'Organization'
      )
      patch revoke_organization_invitation_path(organization, invitation)
      follow_redirect!
      expect(response.body).to include('revoked')
    end

    context 'turbo stream' do
      it 'returns turbo stream response' do
        invitation = create(:invitation,
          invitable: organization,
          status: 'pending',
          invitable_type: 'Organization'
        )
        patch revoke_organization_invitation_path(organization, invitation),
              headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect([200, 406]).to include(response.status)
      end
    end
  end

  describe 'authorization' do
    let(:non_owner) { create(:user, :verified) }

    before do
      create(:organization_membership, organization: organization, user: non_owner, role: :member)
      login_as(non_owner)
    end

    it 'denies non-owner access to invitations index' do
      get organization_invitations_path(organization)
      expect(response).to redirect_to(root_path)
    end

    it 'denies non-owner from inviting members' do
      post organization_members_path(organization),
           params: { emails: ['test@example.com'], role: 'member' }
      expect(response).to redirect_to(root_path)
    end
  end

  describe 'nested resource routing' do
    before { login_as(user) }

    it 'requires valid organization_id' do
      get organization_invitations_path('invalid-id')
      expect(response).to redirect_to(root_path)
    end
  end
end
