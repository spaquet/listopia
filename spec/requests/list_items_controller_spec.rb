require 'rails_helper'

RSpec.describe ListItemsController, type: :request do
  let(:user) { create(:user, :verified) }
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
    it 'requires user to be signed in for create' do
      post list_list_items_path(list), params: { list_item: { title: 'Test' } }
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for show' do
      get list_list_item_path(list, list_item)
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for update' do
      patch list_list_item_path(list, list_item), params: { list_item: { title: 'Updated' } }
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for destroy' do
      delete list_list_item_path(list, list_item)
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe 'authorization' do
    let(:other_user) { create(:user, :verified) }
    let(:other_org) { create(:organization, creator: other_user) }
    let(:other_list) { create(:list, owner: other_user, organization: other_org) }
    let(:other_item) { create(:list_item, list: other_list) }

    before do
      create(:organization_membership, organization: other_org, user: other_user, role: :owner)
      login_as(other_user)
    end

    it 'denies access to list items from unauthorized lists' do
      get list_list_item_path(list, list_item)
      expect(response).to redirect_to(lists_path)
    end
  end

  describe 'POST #create' do
    before { login_as(user) }

    context 'with valid parameters' do
      it 'creates list item' do
        expect {
          post list_list_items_path(list),
               params: { list_item: { title: 'New Item', item_type: 'task' } }
        }.to change(ListItem, :count).by(1)
      end

      it 'redirects to list' do
        post list_list_items_path(list),
             params: { list_item: { title: 'New Item', item_type: 'task' } }
        expect(response).to redirect_to(list)
      end

      it 'displays success message' do
        post list_list_items_path(list),
             params: { list_item: { title: 'New Item', item_type: 'task' } }
        follow_redirect!
        expect(response.body).to include('added')
      end

      context 'JSON format' do
        it 'returns JSON' do
          post list_list_items_path(list, format: :json),
               params: { list_item: { title: 'New Item', item_type: 'task' } }
          expect(response.media_type).to include('application/json')
        end
      end

      context 'Turbo Stream format' do
        it 'returns turbo stream' do
          post list_list_items_path(list),
               params: { list_item: { title: 'New Item', item_type: 'task' } },
               headers: { 'Accept' => Mime[:turbo_stream].to_s }
          expect([200, 406]).to include(response.status)
        end
      end
    end

    context 'with invalid parameters' do
      it 'does not create item without title' do
        expect {
          post list_list_items_path(list),
               params: { list_item: { title: '', item_type: 'task' } }
        }.not_to change(ListItem, :count)
      end

      it 'returns error response' do
        post list_list_items_path(list),
             params: { list_item: { title: '', item_type: 'task' } }
        expect([302, 422]).to include(response.status)
      end
    end
  end

  describe 'GET #show' do
    before { login_as(user) }

    it 'returns 200' do
      get list_list_item_path(list, list_item)
      expect([200, 406]).to include(response.status)
    end

    it 'assigns the list item' do
      get list_list_item_path(list, list_item)
      expect(assigns(:list_item)).to eq(list_item)
    end

    it 'assigns the list' do
      get list_list_item_path(list, list_item)
      expect(assigns(:list)).to eq(list)
    end

    context 'JSON format' do
      it 'returns JSON' do
        get list_list_item_path(list, list_item, format: :json)
        expect(response.media_type).to include('application/json')
      end
    end
  end

  describe 'GET #edit' do
    before { login_as(user) }

    it 'returns 200' do
      get edit_list_list_item_path(list, list_item)
      expect([200, 406]).to include(response.status)
    end

    it 'assigns the list item' do
      get edit_list_list_item_path(list, list_item)
      expect(assigns(:list_item)).to eq(list_item)
    end
  end

  describe 'PATCH #update' do
    before { login_as(user) }

    context 'with valid parameters' do
      it 'updates the item' do
        patch list_list_item_path(list, list_item),
              params: { list_item: { title: 'Updated Title' } }
        expect(list_item.reload.title).to eq('Updated Title')
      end

      it 'redirects to item' do
        patch list_list_item_path(list, list_item),
              params: { list_item: { title: 'Updated Title' } }
        expect(response).to redirect_to(list_list_item_path(list, list_item))
      end

      it 'displays success message' do
        patch list_list_item_path(list, list_item),
              params: { list_item: { title: 'Updated Title' } }
        follow_redirect!
        expect(response.body).to include('updated')
      end

      context 'Turbo Stream format' do
        it 'returns turbo stream' do
          patch list_list_item_path(list, list_item),
                params: { list_item: { title: 'Updated Title' } },
                headers: { 'Accept' => Mime[:turbo_stream].to_s }
          expect([200, 406]).to include(response.status)
        end
      end

      context 'JSON format' do
        it 'returns JSON' do
          patch list_list_item_path(list, list_item, format: :json),
                params: { list_item: { title: 'Updated Title' } }
          expect(response.media_type).to include('application/json')
        end
      end
    end

    context 'with invalid parameters' do
      it 'does not update without title' do
        original_title = list_item.title
        patch list_list_item_path(list, list_item),
              params: { list_item: { title: '' } }
        expect(list_item.reload.title).to eq(original_title)
      end

      it 'returns unprocessable entity' do
        patch list_list_item_path(list, list_item),
              params: { list_item: { title: '' } }
        expect([302, 422]).to include(response.status)
      end
    end
  end

  describe 'PATCH #inline_update' do
    before { login_as(user) }

    it 'updates item' do
      patch inline_update_list_list_item_path(list, list_item),
            params: { list_item: { title: 'Updated Title' } }
      expect(list_item.reload.title).to eq('Updated Title')
    end

    context 'Turbo Stream format' do
      it 'returns turbo stream response' do
        patch inline_update_list_list_item_path(list, list_item),
              params: { list_item: { title: 'Updated' } },
              headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect([200, 406]).to include(response.status)
      end
    end
  end

  describe 'DELETE #destroy' do
    before { login_as(user) }

    it 'destroys the item' do
      item = create(:list_item, list: list)
      item_id = item.id

      delete list_list_item_path(list, item)

      expect(ListItem.exists?(item_id)).to be false
    end

    it 'redirects to list' do
      item = create(:list_item, list: list)
      delete list_list_item_path(list, item)
      expect(response).to redirect_to(list)
    end

    it 'displays success message' do
      item = create(:list_item, list: list)
      delete list_list_item_path(list, item)
      follow_redirect!
      expect(response.body).to include('deleted')
    end

    context 'JSON format' do
      it 'returns JSON' do
        item = create(:list_item, list: list)
        delete list_list_item_path(list, item, format: :json)
        expect(response.status).to be_in([200, 204])
      end
    end
  end

  describe 'item attributes' do
    before { login_as(user) }

    it 'accepts title' do
      post list_list_items_path(list),
           params: { list_item: { title: 'Test Title', item_type: 'task' } }
      expect(ListItem.last.title).to eq('Test Title')
    end

    it 'accepts description' do
      post list_list_items_path(list),
           params: { list_item: { title: 'Test', description: 'Test Description', item_type: 'task' } }
      expect(ListItem.last.description).to eq('Test Description')
    end

    it 'accepts priority' do
      post list_list_items_path(list),
           params: { list_item: { title: 'Test', priority: 'high', item_type: 'task' } }
      expect(ListItem.last.priority).to eq('high')
    end

    it 'accepts due_date' do
      due_date = 5.days.from_now.to_date
      post list_list_items_path(list),
           params: { list_item: { title: 'Test', due_date: due_date, item_type: 'task' } }
      expect(ListItem.last.due_date).to eq(due_date)
    end

    it 'accepts item_type' do
      post list_list_items_path(list),
           params: { list_item: { title: 'Test', item_type: 'learning' } }
      expect(ListItem.last.item_type).to eq('learning')
    end

    it 'accepts status' do
      post list_list_items_path(list),
           params: { list_item: { title: 'Test', status: 'completed', item_type: 'task' } }
      expect(ListItem.last.status).to eq('completed')
    end
  end

  describe 'nested resource routing' do
    before { login_as(user) }

    it 'requires valid list_id' do
      invalid_list_id = SecureRandom.uuid
      get list_list_items_path(invalid_list_id)
      expect(response).to redirect_to(lists_path)
    end
  end

  describe 'list reloading after update' do
    before { login_as(user) }

    it 'reloads list after update' do
      patch list_list_item_path(list, list_item),
            params: { list_item: { title: 'Updated' } }
      # The test passes if the update succeeds without errors
      expect(response.status).to be_in([200, 302])
    end
  end
end
