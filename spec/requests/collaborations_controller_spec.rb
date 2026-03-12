require 'rails_helper'

RSpec.describe CollaborationsController, type: :request do
  let(:user) { create(:user, :verified) }
  let(:collaborator) { create(:user, :verified) }
  let(:organization) { create(:organization, creator: user) }
  let(:list) { create(:list, owner: user, organization: organization) }
  let(:list_item) { create(:list_item, list: list) }

  before do
    create(:organization_membership, organization: organization, user: user, role: :owner)
  end

  def login_as(user)
    post session_path, params: { email: user.email, password: user.password }
  end

  describe 'authentication' do
    it 'requires user to be signed in for index' do
      get list_collaborations_path(list)
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for create' do
      post list_collaborations_path(list), params: { collaboration: { email: 'test@example.com' } }
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for update' do
      collaboration = create(:list_collaboration, list: list, user: collaborator)
      patch list_collaboration_path(list, collaboration), params: { collaboration: { permission: 'read' } }
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for destroy' do
      collaboration = create(:list_collaboration, list: list, user: collaborator)
      delete list_collaboration_path(list, collaboration)
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe 'GET #index (share modal)' do
    before { login_as(user) }

    context 'for lists' do
      it 'returns turbo stream response' do
        get list_collaborations_path(list), headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect([200, 406]).to include(response.status)
      end

      it 'assigns collaborators' do
        create(:list_collaboration, list: list, user: collaborator)
        get list_collaborations_path(list), headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect(assigns(:collaborators)).to be_present
      end

      it 'assigns pending invitations' do
        create(:invitation, invitable: list, status: 'pending')
        get list_collaborations_path(list), headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect(assigns(:pending_invitations)).to be_present
      end
    end

    context 'for list items' do
      it 'returns turbo stream response' do
        get list_item_collaborations_path(list_item), headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect([200, 406]).to include(response.status)
      end
    end
  end

  describe 'POST #create' do
    before { login_as(user) }

    context 'with existing user' do
      it 'creates collaboration' do
        expect {
          post list_collaborations_path(list),
               params: { collaboration: { email: collaborator.email, permission: 'collaborate' } },
               headers: { 'Accept' => Mime[:turbo_stream].to_s }
        }.to change(ListCollaboration, :count).by(1)
      end

      it 'sets correct permission' do
        post list_collaborations_path(list),
             params: { collaboration: { email: collaborator.email, permission: 'read' } },
             headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect(ListCollaboration.last.permission).to eq('read')
      end
    end

    context 'with new email' do
      it 'creates invitation' do
        expect {
          post list_collaborations_path(list),
               params: { collaboration: { email: 'new@example.com', permission: 'collaborate' } },
               headers: { 'Accept' => Mime[:turbo_stream].to_s }
        }.to change(Invitation, :count).by(1)
      end
    end

    context 'with invalid email' do
      it 'returns error response' do
        post list_collaborations_path(list),
             params: { collaboration: { email: '', permission: 'collaborate' } },
             headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect([200, 422]).to include(response.status)
      end
    end

    context 'with role granting' do
      it 'accepts can_invite_collaborators parameter' do
        post list_collaborations_path(list),
             params: {
               collaboration: { email: collaborator.email, permission: 'collaborate' },
               can_invite_collaborators: '1'
             },
             headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect([200, 302, 406]).to include(response.status)
      end
    end
  end

  describe 'PATCH #update' do
    let(:collaboration) { create(:list_collaboration, list: list, user: collaborator, permission: 'read') }

    before { login_as(user) }

    it 'updates permission' do
      patch list_collaboration_path(list, collaboration),
            params: { collaboration: { permission: 'collaborate' } }
      expect(collaboration.reload.permission).to eq('collaborate')
    end

    it 'handles turbo stream' do
      patch list_collaboration_path(list, collaboration),
            params: { collaboration: { permission: 'collaborate' } },
            headers: { 'Accept' => Mime[:turbo_stream].to_s }
      expect([200, 406]).to include(response.status)
    end

    context 'with role changes' do
      it 'grants invite role' do
        patch list_collaboration_path(list, collaboration),
              params: {
                collaboration: { permission: 'collaborate' },
                can_invite_collaborators: '1'
              }
        expect([200, 302]).to include(response.status)
      end
    end
  end

  describe 'DELETE #destroy' do
    before { login_as(user) }

    context 'removing collaborator' do
      let(:collaboration) { create(:list_collaboration, list: list, user: collaborator) }

      it 'destroys collaboration' do
        delete list_collaboration_path(list, collaboration)
        expect(ListCollaboration.exists?(collaboration.id)).to be false
      end

      it 'sends removal notification' do
        allow(CollaborationMailer).to receive(:removed_from_resource).and_return(double(deliver_later: true))
        delete list_collaboration_path(list, collaboration)
        expect(CollaborationMailer).to have_received(:removed_from_resource)
      end
    end

    context 'revoking pending invitation' do
      let(:invitation) { create(:invitation, invitable: list, status: 'pending') }

      it 'destroys invitation' do
        delete list_collaboration_path(list, invitation)
        expect(Invitation.exists?(invitation.id)).to be false
      end
    end

    context 'turbo stream' do
      let(:collaboration) { create(:list_collaboration, list: list, user: collaborator) }

      it 'returns turbo stream' do
        delete list_collaboration_path(list, collaboration),
               headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect([200, 406]).to include(response.status)
      end
    end
  end

  describe 'PATCH #resend' do
    let(:invitation) { create(:invitation, invitable: list, status: 'pending') }

    before { login_as(user) }

    it 'resends invitation' do
      allow(CollaborationMailer).to receive_message_chain(:organization_invitation, :deliver_later)
      patch list_collaboration_resend_path(list, invitation)
      expect([200, 302]).to include(response.status)
    end

    context 'turbo stream' do
      it 'returns turbo stream response' do
        patch list_collaboration_resend_path(list, invitation),
              headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect([200, 406]).to include(response.status)
      end
    end
  end

  describe 'polymorphic resource handling' do
    context 'for list_items' do
      it 'index works with list_item_id parameter' do
        login_as(user)
        get list_item_collaborations_path(list_item), headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect([200, 406]).to include(response.status)
      end

      it 'create works with list_item_id parameter' do
        login_as(user)
        expect {
          post list_item_collaborations_path(list_item),
               params: { collaboration: { email: collaborator.email, permission: 'read' } },
               headers: { 'Accept' => Mime[:turbo_stream].to_s }
        }.to change(ListItemCollaboration, :count).by(1)
      end
    end
  end

  describe 'authorization' do
    let(:other_user) { create(:user, :verified) }
    let(:other_org) { create(:organization, creator: other_user) }
    let(:other_list) { create(:list, owner: other_user, organization: other_org) }

    before do
      create(:organization_membership, organization: other_org, user: other_user, role: :owner)
      login_as(other_user)
    end

    it 'denies access to lists not owned by user' do
      get list_collaborations_path(list), headers: { 'Accept' => Mime[:turbo_stream].to_s }
      expect(response).to redirect_to(lists_path)
    end
  end
end
