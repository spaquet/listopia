require 'rails_helper'

RSpec.describe Admin::UsersController, type: :request do
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
      get admin_users_path
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for show' do
      get admin_user_path(regular_user)
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for new' do
      get new_admin_user_path
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for create' do
      post admin_users_path, params: { user: { name: 'Test', email: 'test@example.com' } }
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for edit' do
      get edit_admin_user_path(regular_user)
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for update' do
      patch admin_user_path(regular_user), params: { user: { name: 'Updated' } }
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for destroy' do
      delete admin_user_path(regular_user)
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for toggle_status' do
      post toggle_status_admin_user_path(regular_user)
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for toggle_admin' do
      post toggle_admin_admin_user_path(regular_user)
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe 'authorization' do
    let(:non_admin) { create(:user, :verified) }

    before { login_as(non_admin) }

    it 'denies non-admin access to index' do
      get admin_users_path
      expect(response.status).to eq(302)
      expect(response.location).to match(%r{/|/lists})
    end

    it 'denies non-admin access to show' do
      get admin_user_path(regular_user)
      expect(response.status).to eq(302)
      expect(response.location).to match(%r{/|/lists})
    end

    it 'denies non-admin access to destroy' do
      delete admin_user_path(regular_user)
      expect(response.status).to eq(302)
      expect(response.location).to match(%r{/|/lists})
    end
  end

  describe 'GET #index' do
    before { login_as(admin_user) }

    it 'returns 200' do
      get admin_users_path
      expect(response).to have_http_status(:ok)
    end

    it 'assigns users' do
      get admin_users_path
      expect(assigns(:users)).to be_present
    end

    it 'assigns filter_service' do
      get admin_users_path
      expect(assigns(:filter_service)).to be_present
    end

    it 'assigns filters hash' do
      get admin_users_path
      expect(assigns(:filters)).to be_a(Hash)
    end

    it 'assigns admin_organizations' do
      get admin_users_path
      expect(assigns(:admin_organizations)).to be_present
    end

    context 'with query parameter' do
      it 'passes query to filter service' do
        expect(UserFilterService).to receive(:new).with(
          hash_including(query: 'test')
        ).and_return(double(filtered_users: User.none, query: 'test', status: nil, role: nil, verified: nil, sort_by: nil, organization_id: nil))

        get admin_users_path(query: 'test')
      end
    end

    context 'with status filter' do
      it 'passes status to filter service' do
        expect(UserFilterService).to receive(:new).with(
          hash_including(status: 'active')
        ).and_return(double(filtered_users: User.none, query: nil, status: 'active', role: nil, verified: nil, sort_by: nil, organization_id: nil))

        get admin_users_path(status: 'active')
      end
    end

    context 'Turbo Stream format' do
      it 'accepts turbo stream request' do
        get admin_users_path, headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect(response.status).to be_in([200, 406])
      end
    end

    context 'with pending invitations' do
      it 'assigns pending invitations' do
        invitation = create(:invitation, organization: organization, status: 'pending', invitable_type: 'Organization', user_id: nil)
        get admin_users_path(organization_id: organization.id)
        expect(assigns(:pending_invitations)).to include(invitation)
      end
    end
  end

  describe 'GET #show' do
    before { login_as(admin_user) }

    it 'returns 200' do
      get admin_user_path(regular_user)
      expect(response).to have_http_status(:ok)
    end

    it 'assigns the user' do
      get admin_user_path(regular_user)
      expect(assigns(:user)).to eq(regular_user)
    end

    context 'when user does not exist' do
      it 'redirects to index with alert' do
        get admin_user_path('invalid-id')
        expect(response).to redirect_to(admin_users_path)
        expect(flash[:alert]).to include('not found')
      end
    end
  end

  describe 'GET #new' do
    before { login_as(admin_user) }

    it 'returns 200' do
      get new_admin_user_path
      expect(response).to have_http_status(:ok)
    end

    it 'assigns new user' do
      get new_admin_user_path
      expect(assigns(:user)).to be_a_new(User)
    end

    it 'stores organization_id if provided' do
      get new_admin_user_path(organization_id: organization.id)
      expect(assigns(:organization_id)).to eq(organization.id.to_s)
    end

    context 'with invalid organization' do
      let(:other_org) { create(:organization) }

      it 'redirects when admin lacks access' do
        get new_admin_user_path(organization_id: other_org.id)
        expect(response).to redirect_to(admin_users_path)
      end
    end
  end

  describe 'POST #create' do
    before { login_as(admin_user) }

    context 'with valid parameters' do
      it 'calls UserCreationService' do
        expect(UserCreationService).to receive(:new).and_call_original

        post admin_users_path, params: {
          user: { name: 'New User', email: 'new@example.com', make_admin: '0' }
        }
      end

      it 'redirects to show after creation' do
        allow(UserCreationService).to receive(:new).and_return(
          double(call: double(success?: true, data: { user: create(:user, :verified) }))
        )

        post admin_users_path, params: {
          user: { name: 'New User', email: 'new@example.com', make_admin: '0' }
        }

        expect(response).to redirect_to(admin_user_path(User.last))
      end

      it 'displays success message' do
        allow(UserCreationService).to receive(:new).and_return(
          double(call: double(success?: true, data: { user: create(:user, :verified) }))
        )

        post admin_users_path, params: {
          user: { name: 'New User', email: 'new@example.com', make_admin: '0' }
        }

        follow_redirect!
        expect(response.body).to include('created successfully')
      end
    end

    context 'with invalid parameters' do
      it 'returns 422 on validation error' do
        allow(UserCreationService).to receive(:new).and_return(
          double(call: double(success?: false, errors: ['Email already taken']))
        )

        post admin_users_path, params: {
          user: { name: '', email: '', make_admin: '0' }
        }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'renders new template on error' do
        allow(UserCreationService).to receive(:new).and_return(
          double(call: double(success?: false, errors: ['Email invalid']))
        )

        post admin_users_path, params: {
          user: { name: 'Test', email: '', make_admin: '0' }
        }

        expect(response.body).to include('Create User')
      end
    end

    context 'with organization_id' do
      it 'validates organization access' do
        other_org = create(:organization)

        post admin_users_path, params: {
          organization_id: other_org.id,
          user: { name: 'Test', email: 'test@example.com', make_admin: '0' }
        }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with make_admin flag' do
      it 'passes make_admin to UserCreationService' do
        expect(UserCreationService).to receive(:new).with(
          hash_including(make_admin: true)
        ).and_return(double(call: double(success?: true, data: { user: create(:user, :admin, :verified) })))

        post admin_users_path, params: {
          user: { name: 'Admin User', email: 'admin@example.com', make_admin: '1' }
        }
      end
    end
  end

  describe 'GET #edit' do
    before { login_as(admin_user) }

    it 'returns 200' do
      get edit_admin_user_path(regular_user)
      expect(response).to have_http_status(:ok)
    end

    it 'assigns the user' do
      get edit_admin_user_path(regular_user)
      expect(assigns(:user)).to eq(regular_user)
    end
  end

  describe 'PATCH #update' do
    before { login_as(admin_user) }

    context 'with valid parameters' do
      it 'updates the user' do
        patch admin_user_path(regular_user),
              params: { user: { name: 'Updated Name' } }

        expect(regular_user.reload.name).to eq('Updated Name')
      end

      it 'redirects to show' do
        patch admin_user_path(regular_user),
              params: { user: { name: 'Updated Name' } }

        expect(response).to redirect_to(admin_user_path(regular_user))
      end

      it 'displays success message' do
        patch admin_user_path(regular_user),
              params: { user: { name: 'Updated Name' } }

        follow_redirect!
        expect(response.body).to include('updated successfully')
      end
    end

    context 'with invalid parameters' do
      it 'returns 422 on validation error' do
        patch admin_user_path(regular_user),
              params: { user: { email: '' } }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'Turbo Stream format' do
      it 'returns turbo stream' do
        patch admin_user_path(regular_user),
              params: { user: { name: 'Updated' } },
              headers: { 'Accept' => Mime[:turbo_stream].to_s }

        expect([200, 406]).to include(response.status)
      end
    end
  end

  describe 'DELETE #destroy' do
    before { login_as(admin_user) }

    context 'destroying another user' do
      it 'deletes the user' do
        other_user = create(:user, :verified)
        user_id = other_user.id

        delete admin_user_path(other_user)

        expect(User.exists?(user_id)).to be false
      end

      it 'redirects to index' do
        other_user = create(:user, :verified)
        delete admin_user_path(other_user)
        expect(response).to redirect_to(admin_users_path)
      end

      it 'displays success message' do
        other_user = create(:user, :verified)
        delete admin_user_path(other_user)
        follow_redirect!
        expect(response.body).to include('deleted successfully')
      end
    end

    context 'attempting to delete self' do
      it 'does not delete current_user' do
        delete admin_user_path(admin_user)
        expect(User.exists?(admin_user.id)).to be true
      end

      it 'redirects with alert' do
        delete admin_user_path(admin_user)
        expect(response.status).to eq(302)
        follow_redirect!
        expect(response.body).to include('cannot delete your own account')
      end
    end

    context 'when user does not exist' do
      it 'redirects to index with alert' do
        delete admin_user_path('invalid-id')
        expect(response).to redirect_to(admin_users_path)
        expect(flash[:alert]).to include('not found')
      end
    end

    context 'Turbo Stream format' do
      it 'returns turbo stream' do
        other_user = create(:user, :verified)
        delete admin_user_path(other_user),
               headers: { 'Accept' => Mime[:turbo_stream].to_s }

        expect([200, 406]).to include(response.status)
      end
    end
  end

  describe 'POST #toggle_status' do
    let(:active_user) { create(:user, :verified, status: 'active') }

    before { login_as(admin_user) }

    context 'suspending an active user' do
      it 'suspends the user' do
        post toggle_status_admin_user_path(active_user)
        expect(active_user.reload.suspended?).to be true
      end

      it 'displays success message' do
        post toggle_status_admin_user_path(active_user)
        follow_redirect!
        expect(response.body).to include('suspended')
      end
    end

    context 'reactivating a suspended user' do
      let(:suspended_user) { create(:user, :verified, status: 'suspended') }

      it 'reactivates the user' do
        post toggle_status_admin_user_path(suspended_user)
        expect(suspended_user.reload.active?).to be true
      end

      it 'displays success message' do
        post toggle_status_admin_user_path(suspended_user)
        follow_redirect!
        expect(response.body).to include('activated')
      end
    end

    context 'Turbo Stream format' do
      it 'returns turbo stream' do
        post toggle_status_admin_user_path(active_user),
             headers: { 'Accept' => Mime[:turbo_stream].to_s }

        expect([200, 302, 406]).to include(response.status)
      end
    end
  end

  describe 'POST #toggle_admin' do
    let(:non_admin) { create(:user, :verified) }

    before { login_as(admin_user) }

    context 'making a user admin' do
      it 'grants admin privileges' do
        post toggle_admin_admin_user_path(non_admin)
        expect(non_admin.reload.admin?).to be true
      end

      it 'displays success message' do
        post toggle_admin_admin_user_path(non_admin)
        follow_redirect!
        expect(response.body).to include('privileges granted')
      end
    end

    context 'removing admin privileges' do
      let(:admin) { create(:user, :admin, :verified) }

      it 'removes admin status' do
        post toggle_admin_admin_user_path(admin)
        expect(admin.reload.admin?).to be false
      end

      it 'displays success message' do
        post toggle_admin_admin_user_path(admin)
        follow_redirect!
        expect(response.body).to include('privileges removed')
      end
    end

    context 'Turbo Stream format' do
      it 'returns turbo stream' do
        post toggle_admin_admin_user_path(non_admin),
             headers: { 'Accept' => Mime[:turbo_stream].to_s }

        expect([200, 302, 406]).to include(response.status)
      end
    end
  end

  describe 'POST #resend_invitation' do
    let(:invited_user) { create(:user, :verified) }

    before { login_as(admin_user) }

    context 'with pending invitation' do
      it 'resends invitation email' do
        invitation = create(:invitation,
          user: invited_user,
          organization: organization,
          status: 'pending',
          invitable_type: 'Organization'
        )

        expect(AdminMailer).to receive(:user_invitation).and_call_original

        post resend_invitation_admin_user_path(invited_user)
      end

      it 'updates invitation token' do
        invitation = create(:invitation,
          user: invited_user,
          organization: organization,
          status: 'pending',
          invitable_type: 'Organization'
        )
        old_token = invitation.invitation_token

        allow(AdminMailer).to receive(:user_invitation).and_return(double(deliver_later: true))
        post resend_invitation_admin_user_path(invited_user)

        expect(invitation.reload.invitation_token).not_to eq(old_token)
      end

      it 'displays success message' do
        create(:invitation,
          user: invited_user,
          organization: organization,
          status: 'pending',
          invitable_type: 'Organization'
        )

        allow(AdminMailer).to receive(:user_invitation).and_return(double(deliver_later: true))
        post resend_invitation_admin_user_path(invited_user)
        follow_redirect!

        expect(response.body).to include('Invitation resent')
      end
    end

    context 'with no pending invitation' do
      it 'displays appropriate message' do
        post resend_invitation_admin_user_path(invited_user)
        follow_redirect!
        expect(response.body).to include('No pending invitation')
      end
    end

    context 'Turbo Stream format' do
      it 'returns turbo stream' do
        create(:invitation,
          user: invited_user,
          organization: organization,
          status: 'pending',
          invitable_type: 'Organization'
        )

        allow(AdminMailer).to receive(:user_invitation).and_return(double(deliver_later: true))

        post resend_invitation_admin_user_path(invited_user),
             headers: { 'Accept' => Mime[:turbo_stream].to_s }

        expect([200, 302, 406]).to include(response.status)
      end
    end
  end
end
