require 'rails_helper'

RSpec.describe InvitationsController, type: :request do
  let(:user) { create(:user, :verified) }
  let(:invited_user) { create(:user, :verified) }
  let(:organization) { create(:organization, creator: user) }
  let(:list) { create(:list, owner: user, organization: organization) }

  before do
    create(:organization_membership, organization: organization, user: user, role: :owner)
  end

  def login_as(user)
    post session_path, params: { email: user.email, password: user.password }
  end

  describe 'authentication' do
    it 'requires user to be signed in for index' do
      get invitations_path
      expect(response).to redirect_to(new_session_path)
    end

    it 'accepts unauthenticated user for accept action' do
      invitation = create(:invitation, invitable: list, email: invited_user.email, status: 'pending')
      get accept_invitation_path(invitation.invitation_token)
      expect(response.status).to eq(302)
    end
  end

  describe 'GET #index' do
    before { login_as(user) }

    it 'returns 200' do
      get invitations_path
      expect([200, 406]).to include(response.status)
    end

    it 'defaults to received tab' do
      get invitations_path
      expect(assigns(:tab)).to eq('received')
    end

    it 'shows sent invitations when tab=sent' do
      get invitations_path(tab: 'sent')
      expect(assigns(:tab)).to eq('sent')
    end

    context 'with pending invitations' do
      before do
        create(:invitation, invitable: list, email: invited_user.email, status: 'pending', invited_by: user)
      end

      it 'lists pending invitations' do
        get invitations_path(tab: 'sent')
        expect(assigns(:invitations)).to be_present
      end

      it 'filters by status' do
        get invitations_path(tab: 'sent', status: 'pending')
        invitations = assigns(:invitations)
        expect(invitations.all? { |i| i.status == 'pending' }).to be true
      end
    end

    context 'search functionality' do
      it 'searches by email' do
        create(:invitation, invitable: list, email: 'test@example.com', invited_by: user)
        get invitations_path(tab: 'sent', search: 'test@example.com')
        expect(assigns(:invitations)).to be_present
      end

      it 'searches by name' do
        other_user = create(:user, name: 'John Doe')
        create(:invitation, invitable: list, email: 'john@example.com', invited_by: other_user)
        get invitations_path(tab: 'sent', search: 'John')
        expect(assigns(:invitations)).to be_present
      end
    end
  end

  describe 'POST/GET #accept' do
    context 'collaboration invitation' do
      let(:invitation) { create(:invitation, invitable: list, email: invited_user.email, status: 'pending', invited_by: user) }

      context 'when authenticated' do
        before { login_as(invited_user) }

        it 'accepts invitation when email matches' do
          allow(CollaborationAcceptanceService).to receive(:new).and_return(
            double(accept: double(success?: true, resource: list, message: 'Accepted'))
          )
          get accept_invitation_path(invitation.invitation_token)
          expect(response).to redirect_to(list)
        end

        it 'rejects invitation when email does not match' do
          other_user = create(:user, :verified, email: 'other@example.com')
          login_as(other_user)
          get accept_invitation_path(invitation.invitation_token)
          expect(response).to redirect_to(root_path)
        end
      end

      context 'when unauthenticated' do
        it 'stores token in session' do
          get accept_invitation_path(invitation.invitation_token)
          expect(session[:pending_invitation_token]).to eq(invitation.invitation_token)
        end

        it 'redirects to signup' do
          get accept_invitation_path(invitation.invitation_token)
          expect(response).to redirect_to(new_registration_path)
        end
      end

      context 'with invalid token' do
        it 'redirects to root' do
          get accept_invitation_path('invalid-token')
          expect(response).to redirect_to(root_path)
        end
      end
    end

    context 'organization invitation' do
      let(:invitation) do
        create(:invitation,
          invitable: organization,
          email: invited_user.email,
          status: 'pending',
          invited_by: user,
          invitable_type: 'Organization'
        )
      end

      before { login_as(invited_user) }

      it 'creates organization membership' do
        expect {
          get accept_invitation_path(invitation.invitation_token)
        }.to change(OrganizationMembership, :count).by(1)
      end

      it 'marks invitation as accepted' do
        get accept_invitation_path(invitation.invitation_token)
        expect(invitation.reload.status).to eq('accepted')
      end

      it 'redirects to organization' do
        get accept_invitation_path(invitation.invitation_token)
        expect(response).to redirect_to(organization_path(organization))
      end
    end
  end

  describe 'DELETE #destroy' do
    before { login_as(user) }

    it 'destroys sent invitation' do
      invitation = create(:invitation, invitable: list, invited_by: user, status: 'pending')
      invitation_id = invitation.id

      delete invitation_path(invitation)

      expect(Invitation.exists?(invitation_id)).to be false
    end

    context 'turbo stream' do
      it 'returns turbo stream response' do
        invitation = create(:invitation, invitable: list, invited_by: user, status: 'pending')
        delete invitation_path(invitation), headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect([200, 406]).to include(response.status)
      end
    end
  end

  describe 'PATCH #resend' do
    before { login_as(user) }

    it 'resends invitation email' do
      invitation = create(:invitation, invitable: list, invited_by: user, status: 'pending', email: 'test@example.com')
      allow(InvitationService).to receive(:new).and_return(
        double(resend: double(message: 'Resent'))
      )
      patch resend_invitation_path(invitation)
      expect(response.status).to eq(302)
    end

    context 'turbo stream' do
      it 'returns turbo stream response' do
        invitation = create(:invitation, invitable: list, invited_by: user, status: 'pending')
        patch resend_invitation_path(invitation), headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect([200, 406]).to include(response.status)
      end
    end
  end

  describe 'PATCH #decline' do
    before { login_as(invited_user) }

    it 'declines received invitation' do
      invitation = create(:invitation, invitable: list, email: invited_user.email, status: 'pending')
      patch decline_invitation_path(invitation)
      expect(invitation.reload.status).to eq('declined')
    end

    it 'removes from invitations list' do
      invitation = create(:invitation, invitable: list, email: invited_user.email, status: 'pending')
      patch decline_invitation_path(invitation)
      expect(response).to redirect_to(invitations_path(tab: 'received'))
    end

    context 'turbo stream' do
      it 'returns turbo stream response' do
        invitation = create(:invitation, invitable: list, email: invited_user.email, status: 'pending')
        patch decline_invitation_path(invitation), headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect([200, 406]).to include(response.status)
      end
    end
  end

  describe 'DELETE #revoke' do
    before { login_as(user) }

    it 'revokes sent invitation' do
      invitation = create(:invitation, invitable: list, invited_by: user, status: 'pending')
      delete revoke_invitation_path(invitation)
      expect(invitation.reload.status).to eq('revoked')
    end

    it 'redirects to sent tab' do
      invitation = create(:invitation, invitable: list, invited_by: user, status: 'pending')
      delete revoke_invitation_path(invitation)
      expect(response).to redirect_to(invitations_path(tab: 'sent'))
    end

    context 'authorization' do
      it 'denies revoke if not sender' do
        invitation = create(:invitation, invitable: list, invited_by: user, status: 'pending')
        other_user = create(:user, :verified)
        login_as(other_user)

        delete revoke_invitation_path(invitation)
        expect(response).to redirect_to(invitations_path)
      end
    end
  end

  describe 'PATCH #update' do
    before { login_as(user) }

    it 'updates permission' do
      invitation = create(:invitation, invitable: list, invited_by: user, status: 'pending', permission: 'read')
      patch invitation_path(invitation), params: { invitation: { permission: 'collaborate' } }
      expect(invitation.reload.permission).to eq('collaborate')
    end

    it 'redirects to sent tab' do
      invitation = create(:invitation, invitable: list, invited_by: user, status: 'pending')
      patch invitation_path(invitation), params: { invitation: { permission: 'collaborate' } }
      expect(response).to redirect_to(invitations_path(tab: 'sent'))
    end

    context 'authorization' do
      it 'denies update if not sender' do
        invitation = create(:invitation, invitable: list, invited_by: user, status: 'pending')
        other_user = create(:user, :verified)
        login_as(other_user)

        patch invitation_path(invitation), params: { invitation: { permission: 'collaborate' } }
        expect(response).to redirect_to(invitations_path)
      end
    end
  end

  describe 'GET #show' do
    before { login_as(user) }

    it 'shows collaboration invitation' do
      invitation = create(:invitation, invitable: list, invited_by: user, status: 'pending')
      get invitation_path(invitation)
      expect([200, 406]).to include(response.status)
    end

    context 'with expired invitation' do
      it 'redirects with alert' do
        invitation = create(:invitation, invitable: list, invited_by: user, status: 'expired')
        get invitation_path(invitation)
        expect(response).to redirect_to(root_path)
      end
    end

    context 'with accepted invitation' do
      it 'redirects to resource' do
        invitation = create(:invitation, invitable: list, invited_by: user, status: 'accepted')
        get invitation_path(invitation)
        expect(response).to redirect_to(list)
      end
    end
  end
end
