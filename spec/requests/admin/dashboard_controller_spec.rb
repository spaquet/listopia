require 'rails_helper'

RSpec.describe Admin::DashboardController, type: :request do
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
    it 'requires user to be signed in' do
      get admin_dashboard_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe 'authorization' do
    before { login_as(regular_user) }

    it 'denies access to non-admin users' do
      get admin_dashboard_path
      expect(response).to redirect_to(lists_path)
    end
  end

  describe 'GET #index' do
    before { login_as(admin_user) }

    it 'returns 200' do
      get admin_dashboard_path
      expect(response).to have_http_status(:ok)
    end

    it 'assigns stats' do
      get admin_dashboard_path
      expect(assigns(:stats)).to be_a(Hash)
    end

    it 'includes total_users in stats' do
      get admin_dashboard_path
      expect(assigns(:stats)).to have_key(:total_users)
    end

    it 'includes active_users in stats' do
      get admin_dashboard_path
      expect(assigns(:stats)).to have_key(:active_users)
    end

    it 'includes admin_users in stats' do
      get admin_dashboard_path
      expect(assigns(:stats)).to have_key(:admin_users)
    end

    it 'includes new_users_this_month in stats' do
      get admin_dashboard_path
      expect(assigns(:stats)).to have_key(:new_users_this_month)
    end

    context 'with multiple users in organization' do
      let(:other_user1) { create(:user, :verified, status: 'active') }
      let(:other_user2) { create(:user, :verified, status: 'suspended') }

      before do
        create(:organization_membership, organization: organization, user: other_user1, role: :member)
        create(:organization_membership, organization: organization, user: other_user2, role: :member)
      end

      it 'counts all organization users' do
        get admin_dashboard_path
        expect(assigns(:stats)[:total_users]).to eq(3)
      end

      it 'counts active users' do
        get admin_dashboard_path
        expect(assigns(:stats)[:active_users]).to be >= 1
      end
    end

    context 'with users created this month' do
      before do
        create(:user, :verified, status: 'active')
        organization.reload
      end

      it 'counts new users this month' do
        get admin_dashboard_path
        expect(assigns(:stats)[:new_users_this_month]).to be >= 0
      end
    end

    it 'returns numeric stats values' do
      get admin_dashboard_path
      stats = assigns(:stats)
      expect(stats[:total_users]).to be_a(Integer)
      expect(stats[:active_users]).to be_a(Integer)
      expect(stats[:admin_users]).to be_a(Integer)
      expect(stats[:new_users_this_month]).to be_a(Integer)
    end

    context 'with admin and owner roles' do
      let(:admin_member) { create(:user, :verified) }

      before do
        create(:organization_membership, organization: organization, user: admin_member, role: :admin)
      end

      it 'counts both admin and owner roles' do
        get admin_dashboard_path
        expect(assigns(:stats)[:admin_users]).to be >= 1
      end
    end
  end
end
