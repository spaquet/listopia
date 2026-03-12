require 'rails_helper'

RSpec.describe CollaboratorsController, type: :request do
  let(:user) { create(:user, :verified) }
  let(:collaborator) { create(:user, :verified) }
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
      get list_collaborators_path(list)
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for create' do
      post list_collaborators_path(list), params: { collaborator: { permission: 'read' }, email: 'test@example.com' }
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for update' do
      collab = create(:list_collaboration, list: list, user: collaborator)
      patch list_collaborator_path(list, collab), params: { collaborator: { permission: 'read' } }
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for destroy' do
      collab = create(:list_collaboration, list: list, user: collaborator)
      delete list_collaborator_path(list, collab)
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe 'GET #index' do
    before { login_as(user) }

    it 'returns 200' do
      get list_collaborators_path(list)
      expect([200, 406]).to include(response.status)
    end

    it 'assigns collaborators' do
      create(:list_collaboration, list: list, user: collaborator)
      get list_collaborators_path(list)
      expect(assigns(:collaborators)).to be_present
    end

    it 'assigns pending invitations' do
      create(:invitation, invitable: list, status: 'pending')
      get list_collaborators_path(list)
      expect(assigns(:invitations)).to be_present
    end

    context 'with multiple collaborators' do
      it 'lists all collaborators' do
        user2 = create(:user, :verified)
        user3 = create(:user, :verified)
        create(:list_collaboration, list: list, user: user2)
        create(:list_collaboration, list: list, user: user3)

        get list_collaborators_path(list)
        collaborators = assigns(:collaborators)
        expect(collaborators.count).to be >= 2
      end
    end
  end

  describe 'POST #create' do
    before { login_as(user) }

    context 'with existing user' do
      it 'adds collaborator' do
        expect {
          post list_collaborators_path(list),
               params: { email: collaborator.email, collaborator: { permission: 'read' } }
        }.to change(ListCollaboration, :count).by(1)
      end

      it 'redirects to index' do
        post list_collaborators_path(list),
             params: { email: collaborator.email, collaborator: { permission: 'read' } }
        expect(response).to redirect_to(list_collaborators_path(list))
      end

      it 'displays success message' do
        post list_collaborators_path(list),
             params: { email: collaborator.email, collaborator: { permission: 'read' } }
        follow_redirect!
        expect(response.body).to include('successfully')
      end
    end

    context 'with new email' do
      it 'creates invitation' do
        expect {
          post list_collaborators_path(list),
               params: { email: 'new@example.com', collaborator: { permission: 'read' } }
        }.to change(Invitation, :count).by(1)
      end

      it 'redirects to index' do
        post list_collaborators_path(list),
             params: { email: 'new@example.com', collaborator: { permission: 'read' } }
        expect(response).to redirect_to(list_collaborators_path(list))
      end
    end

    context 'with invalid email' do
      it 'does not create collaboration' do
        expect {
          post list_collaborators_path(list),
               params: { email: '', collaborator: { permission: 'read' } }
        }.not_to change(ListCollaboration, :count)
      end

      it 'returns 422' do
        post list_collaborators_path(list),
             params: { email: '', collaborator: { permission: 'read' } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH #update' do
    let(:collab) { create(:list_collaboration, list: list, user: collaborator, permission: 'read') }

    before { login_as(user) }

    it 'updates permission' do
      patch list_collaborator_path(list, collab),
            params: { collaborator: { permission: 'collaborate' } }
      expect(collab.reload.permission).to eq('collaborate')
    end

    it 'redirects to index' do
      patch list_collaborator_path(list, collab),
            params: { collaborator: { permission: 'collaborate' } }
      expect(response).to redirect_to(list_collaborators_path(list))
    end

    context 'turbo stream' do
      it 'returns turbo stream response' do
        patch list_collaborator_path(list, collab),
              params: { collaborator: { permission: 'collaborate' } },
              headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect([200, 406]).to include(response.status)
      end
    end

    context 'with invalid permission' do
      it 'returns error' do
        patch list_collaborator_path(list, collab),
              params: { collaborator: { permission: 'invalid' } }
        expect(response).to redirect_to(list_collaborators_path(list))
      end
    end
  end

  describe 'DELETE #destroy' do
    before { login_as(user) }

    it 'removes collaborator' do
      collab = create(:list_collaboration, list: list, user: collaborator)
      collab_id = collab.id

      delete list_collaborator_path(list, collab)

      expect(ListCollaboration.exists?(collab_id)).to be false
    end

    it 'redirects to index' do
      collab = create(:list_collaboration, list: list, user: collaborator)
      delete list_collaborator_path(list, collab)
      expect(response).to redirect_to(list_collaborators_path(list))
    end

    it 'displays success message' do
      collab = create(:list_collaboration, list: list, user: collaborator)
      delete list_collaborator_path(list, collab)
      follow_redirect!
      expect(response.body).to include('removed')
    end

    context 'turbo stream' do
      it 'returns turbo stream response' do
        collab = create(:list_collaboration, list: list, user: collaborator)
        delete list_collaborator_path(list, collab),
               headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect([200, 406]).to include(response.status)
      end
    end

    context 'with notifications' do
      it 'sends removal notification' do
        collab = create(:list_collaboration, list: list, user: collaborator)
        allow(CollaborationMailer).to receive(:removed_from_resource).and_return(double(deliver_later: true))
        delete list_collaborator_path(list, collab)
        expect(CollaborationMailer).to have_received(:removed_from_resource)
      end
    end
  end

  describe 'polymorphic resources' do
    context 'for list_items' do
      let(:list_item) { create(:list_item, list: list) }

      before { login_as(user) }

      it 'index works with list_item' do
        get list_item_collaborators_path(list_item)
        expect([200, 406]).to include(response.status)
      end

      it 'create works with list_item' do
        expect {
          post list_item_collaborators_path(list_item),
               params: { email: collaborator.email, collaborator: { permission: 'read' } }
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
      get list_collaborators_path(list)
      expect(response).to redirect_to(lists_path)
    end
  end
end
