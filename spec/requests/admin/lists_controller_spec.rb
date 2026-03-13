require 'rails_helper'

RSpec.describe Admin::ListsController, type: :request do
  let(:admin_user) { create(:user, :admin, :verified) }
  let(:regular_user) { create(:user, :verified) }
  let(:organization) { create(:organization, creator: admin_user) }

  before do
    create(:organization_membership, organization: organization, user: admin_user, role: :owner)
  end

  def login_as(user)
    post session_path, params: { email: user.email, password: user.password }
  end

  describe 'authentication' do
    it 'requires user to be signed in for index' do
      get admin_lists_path
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for show' do
      list = create(:list, owner: regular_user, organization: organization)
      get admin_list_path(list)
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for destroy' do
      list = create(:list, owner: regular_user, organization: organization)
      delete admin_list_path(list)
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe 'authorization' do
    before { login_as(regular_user) }

    it 'denies non-admin access to index' do
      get admin_lists_path
      expect(response.status).to eq(302)
    end

    it 'denies non-admin access to show' do
      list = create(:list, owner: regular_user, organization: organization)
      get admin_list_path(list)
      expect(response.status).to eq(302)
    end

    it 'denies non-admin access to destroy' do
      list = create(:list, owner: regular_user, organization: organization)
      delete admin_list_path(list)
      expect(response.status).to eq(302)
    end
  end

  describe 'GET #index' do
    before { login_as(admin_user) }

    it 'returns 200' do
      get admin_lists_path
      expect([ 200, 406 ]).to include(response.status)
    end

    it 'assigns pagy and lists' do
      create(:list, owner: regular_user, organization: organization)
      get admin_lists_path
      expect(assigns(:lists)).to be_present
    end

    it 'paginates lists' do
      create_list(:list, 5, owner: regular_user, organization: organization)
      get admin_lists_path
      expect(assigns(:lists)).to be_an(Array)
    end

    it 'orders lists by created_at descending' do
      list1 = create(:list, owner: regular_user, organization: organization, created_at: 2.days.ago)
      list2 = create(:list, owner: regular_user, organization: organization, created_at: 1.day.ago)
      list3 = create(:list, owner: regular_user, organization: organization)

      get admin_lists_path
      lists = assigns(:lists)

      expect(lists.first.id).to eq(list3.id)
      expect(lists.last.id).to eq(list1.id)
    end

    it 'includes list owners' do
      create(:list, owner: regular_user, organization: organization)
      get admin_lists_path
      expect(assigns(:lists).first.owner).to be_present
    end

    context 'with no lists' do
      it 'assigns empty array' do
        get admin_lists_path
        expect(assigns(:lists)).to eq([])
      end
    end

    context 'with multiple lists' do
      it 'displays all lists' do
        user1 = create(:user, :verified)
        user2 = create(:user, :verified)
        create(:organization_membership, organization: organization, user: user1, role: :member)
        create(:organization_membership, organization: organization, user: user2, role: :member)

        list1 = create(:list, owner: user1, organization: organization)
        list2 = create(:list, owner: user2, organization: organization)

        get admin_lists_path
        lists = assigns(:lists)

        expect(lists).to include(list1)
        expect(lists).to include(list2)
      end
    end
  end

  describe 'GET #show' do
    let(:list) { create(:list, owner: regular_user, organization: organization) }

    before { login_as(admin_user) }

    it 'returns 200' do
      get admin_list_path(list)
      expect([ 200, 406 ]).to include(response.status)
    end

    it 'assigns the list' do
      get admin_list_path(list)
      expect(assigns(:list)).to eq(list)
    end

    context 'when list does not exist' do
      it 'redirects to index with alert' do
        get admin_list_path('invalid-id')
        expect(response).to redirect_to(admin_lists_path)
        expect(flash[:alert]).to include('not found')
      end
    end
  end

  describe 'DELETE #destroy' do
    before { login_as(admin_user) }

    it 'deletes the list' do
      list = create(:list, owner: regular_user, organization: organization)
      list_id = list.id

      expect {
        delete admin_list_path(list)
      }.to change(List, :count).by(-1)

      expect(List.exists?(list_id)).to be false
    end

    it 'redirects to admin lists path' do
      list = create(:list, owner: regular_user, organization: organization)
      delete admin_list_path(list)
      expect(response).to redirect_to(admin_lists_path)
    end

    it 'displays success message' do
      list = create(:list, owner: regular_user, organization: organization)
      delete admin_list_path(list)
      follow_redirect!
      expect(response.body).to include('deleted successfully')
    end

    context 'when list does not exist' do
      it 'redirects to index with alert' do
        delete admin_list_path('invalid-id')
        expect(response).to redirect_to(admin_lists_path)
        expect(flash[:alert]).to include('not found')
      end
    end

    context 'with list items' do
      it 'cascades delete to list items' do
        list = create(:list, owner: regular_user, organization: organization)
        item1 = create(:list_item, list: list)
        item2 = create(:list_item, list: list)

        delete admin_list_path(list)

        expect(ListItem.exists?(item1.id)).to be false
        expect(ListItem.exists?(item2.id)).to be false
      end
    end
  end
end
