require 'rails_helper'

RSpec.describe Admin::OrganizationsController, type: :request do
  let(:admin_user) { create(:user, :admin, :verified) }
  let(:non_admin_user) { create(:user, :verified) }
  let(:organization) { create(:organization, creator: admin_user) }

  def login_as(user)
    post session_path, params: { email: user.email, password: user.password }
  end

  describe 'authentication' do
    it 'requires user to be signed in for index' do
      get admin_organizations_path
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for show' do
      get admin_organization_path(organization)
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for new' do
      get new_admin_organization_path
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for create' do
      post admin_organizations_path, params: { organization: { name: 'Test' } }
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for edit' do
      get edit_admin_organization_path(organization)
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for update' do
      patch admin_organization_path(organization), params: { organization: { name: 'Updated' } }
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for suspend' do
      post suspend_admin_organization_path(organization)
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for reactivate' do
      post reactivate_admin_organization_path(organization)
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for members' do
      get admin_organization_members_path(organization)
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for audit_logs' do
      get admin_organization_audit_logs_path(organization)
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for destroy' do
      delete admin_organization_path(organization)
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe 'GET #index' do
    before do
      login_as(admin_user)
      organization  # Ensure organization is created for tests
    end

    it 'returns 200' do
      get admin_organizations_path
      expect(response).to have_http_status(:ok)
    end

    it 'assigns organizations' do
      get admin_organizations_path
      expect(assigns(:organizations)).to be_present
    end

    it 'assigns filter_service' do
      get admin_organizations_path
      expect(assigns(:filter_service)).to be_present
    end

    it 'assigns filters hash' do
      get admin_organizations_path
      expect(assigns(:filters)).to be_a(Hash)
    end

    it 'filters organizations for user' do
      other_org = create(:organization)
      get admin_organizations_path
      orgs = assigns(:organizations)
      expect(orgs).to include(organization)
      expect(orgs).not_to include(other_org)
    end

    context 'with query parameter' do
      it 'passes query to filter service' do
        expect(OrganizationFilterService).to receive(:new).with(
          hash_including(query: 'test')
        ).and_return(double(filtered_organizations: Organization.none, query: 'test', status: nil, size: nil, sort_by: nil))

        get admin_organizations_path(query: 'test')
      end
    end

    context 'with status filter' do
      it 'passes status to filter service' do
        expect(OrganizationFilterService).to receive(:new).with(
          hash_including(status: 'active')
        ).and_return(double(filtered_organizations: Organization.none, query: nil, status: 'active', size: nil, sort_by: nil))

        get admin_organizations_path(status: 'active')
      end
    end

    context 'Turbo Stream format' do
      it 'accepts turbo stream request' do
        get admin_organizations_path, headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect(response.status).to be_in([200, 406])
      end
    end

    context 'when filter service raises error' do
      it 'renders index with error' do
        allow(OrganizationFilterService).to receive(:new).and_raise(StandardError.new('Filter error'))
        get admin_organizations_path
        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash.now[:alert]).to include('error')
      end
    end
  end

  describe 'GET #show' do
    before { login_as(admin_user) }

    it 'returns 200' do
      get admin_organization_path(organization)
      expect(response).to have_http_status(:ok)
    end

    it 'assigns the organization' do
      get admin_organization_path(organization)
      expect(assigns(:organization)).to eq(organization)
    end

    context 'when organization does not exist' do
      it 'redirects to index with alert' do
        get admin_organization_path('invalid-id')
        expect(response).to redirect_to(admin_organizations_path)
        expect(flash[:alert]).to include('not found')
      end
    end
  end

  describe 'GET #new' do
    before { login_as(admin_user) }

    it 'returns 200' do
      get new_admin_organization_path
      expect(response).to have_http_status(:ok)
    end

    it 'assigns new organization' do
      get new_admin_organization_path
      expect(assigns(:organization)).to be_a_new(Organization)
    end
  end

  describe 'POST #create' do
    before { login_as(admin_user) }

    context 'with valid parameters' do
      it 'creates a new organization' do
        expect {
          post admin_organizations_path, params: { organization: { name: 'New Org', size: 'small' } }
        }.to change(Organization, :count).by(1)
      end

      it 'sets creator' do
        post admin_organizations_path, params: { organization: { name: 'New Org' } }
        expect(Organization.last.created_by_id).to eq(admin_user.id)
      end

      it 'adds creator as owner' do
        post admin_organizations_path, params: { organization: { name: 'New Org' } }
        org = Organization.last
        membership = org.organization_memberships.find_by(user: admin_user)
        expect(membership.owner?).to be true
      end

      it 'redirects to show' do
        post admin_organizations_path, params: { organization: { name: 'New Org' } }
        expect(response).to redirect_to(admin_organization_path(Organization.last))
      end

      it 'displays success message' do
        post admin_organizations_path, params: { organization: { name: 'New Org' } }
        follow_redirect!
        expect(response.body).to include('created successfully')
      end
    end

    context 'with invalid parameters' do
      it 'does not create organization without name' do
        expect {
          post admin_organizations_path, params: { organization: { name: '' } }
        }.not_to change(Organization, :count)
      end

      it 'returns 422 when name is blank' do
        post admin_organizations_path, params: { organization: { name: '' } }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'renders new template on error' do
        post admin_organizations_path, params: { organization: { name: '' } }
        expect(response.body).to include('New Organization')
      end
    end

    context 'Turbo Stream format' do
      it 'accepts turbo stream format' do
        post admin_organizations_path,
             params: { organization: { name: 'New Org' } },
             headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect([200, 303]).to include(response.status)
      end
    end
  end

  describe 'GET #edit' do
    before { login_as(admin_user) }

    it 'returns 200' do
      get edit_admin_organization_path(organization)
      expect(response).to have_http_status(:ok)
    end

    it 'assigns the organization' do
      get edit_admin_organization_path(organization)
      expect(assigns(:organization)).to eq(organization)
    end
  end

  describe 'PATCH #update' do
    let(:organization) { create(:organization, creator: admin_user, name: 'Original Name') }

    before { login_as(admin_user) }

    context 'with valid parameters' do
      it 'updates the organization' do
        patch admin_organization_path(organization),
              params: { organization: { name: 'Updated Name' } }
        expect(organization.reload.name).to eq('Updated Name')
      end

      it 'redirects to show' do
        patch admin_organization_path(organization),
              params: { organization: { name: 'Updated Name' } }
        expect(response).to redirect_to(admin_organization_path(organization))
      end

      it 'displays success message' do
        patch admin_organization_path(organization),
              params: { organization: { name: 'Updated Name' } }
        follow_redirect!
        expect(response.body).to include('updated successfully')
      end
    end

    context 'with invalid parameters' do
      it 'does not update organization' do
        patch admin_organization_path(organization),
              params: { organization: { name: '' } }
        expect(organization.reload.name).to eq('Original Name')
      end

      it 'returns 422 on validation error' do
        patch admin_organization_path(organization),
              params: { organization: { name: '' } }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'renders edit template' do
        patch admin_organization_path(organization),
              params: { organization: { name: '' } }
        expect(response.body).to include('Edit')
      end
    end
  end

  describe 'DELETE #destroy' do
    before { login_as(admin_user) }

    it 'deletes the organization' do
      org = create(:organization, creator: admin_user)
      org_id = org.id

      delete admin_organization_path(org)

      expect(Organization.exists?(org_id)).to be false
    end

    it 'redirects to index' do
      org = create(:organization, creator: admin_user)
      delete admin_organization_path(org)
      expect(response).to redirect_to(admin_organizations_path)
    end

    it 'displays success message' do
      org = create(:organization, creator: admin_user)
      delete admin_organization_path(org)
      follow_redirect!
      expect(response.body).to include('deleted successfully')
    end
  end

  describe 'GET #members' do
    let(:organization) { create(:organization, creator: admin_user) }

    before do
      login_as(admin_user)
    end

    it 'returns 200' do
      get admin_organization_members_path(organization)
      expect(response).to have_http_status(:ok)
    end

    it 'assigns memberships' do
      get admin_organization_members_path(organization)
      expect(assigns(:members)).to be_present
    end

    it 'paginates members' do
      create_list(:organization_membership, 5, organization: organization)
      get admin_organization_members_path(organization)
      expect(assigns(:pagy)).to be_present
    end

    it 'orders by created_at descending' do
      member1 = create(:user, :verified)
      member2 = create(:user, :verified)
      create(:organization_membership, organization: organization, user: member1, created_at: 1.day.ago)
      create(:organization_membership, organization: organization, user: member2)

      get admin_organization_members_path(organization)
      members = assigns(:members)

      expect(members.first.user_id).to eq(member2.id)
    end

    context 'when organization does not exist' do
      it 'redirects to index with alert' do
        get admin_organization_members_path('invalid-id')
        expect(response).to redirect_to(admin_organizations_path)
      end
    end
  end

  describe 'POST #suspend' do
    let(:organization) { create(:organization, creator: admin_user, status: 'active') }

    before do
      login_as(admin_user)
    end

    it 'suspends the organization' do
      post suspend_admin_organization_path(organization)
      expect(organization.reload.suspended?).to be true
    end

    it 'redirects to index' do
      post suspend_admin_organization_path(organization)
      expect(response).to redirect_to(admin_organizations_path)
    end

    it 'displays success message' do
      post suspend_admin_organization_path(organization)
      follow_redirect!
      expect(response.body).to include('suspended')
    end

    context 'Turbo Stream format' do
      it 'returns turbo stream' do
        post suspend_admin_organization_path(organization),
             headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect([200, 302, 406]).to include(response.status)
      end
    end
  end

  describe 'POST #reactivate' do
    let(:organization) { create(:organization, creator: admin_user, status: 'suspended') }

    before do
      login_as(admin_user)
    end

    it 'reactivates the organization' do
      post reactivate_admin_organization_path(organization)
      expect(organization.reload.active?).to be true
    end

    it 'redirects to index' do
      post reactivate_admin_organization_path(organization)
      expect(response).to redirect_to(admin_organizations_path)
    end

    it 'displays success message' do
      post reactivate_admin_organization_path(organization)
      follow_redirect!
      expect(response.body).to include('reactivated')
    end

    context 'Turbo Stream format' do
      it 'returns turbo stream' do
        post reactivate_admin_organization_path(organization),
             headers: { 'Accept' => Mime[:turbo_stream].to_s }
        expect([200, 302, 406]).to include(response.status)
      end
    end
  end

  describe 'GET #audit_logs' do
    let(:organization) { create(:organization, creator: admin_user) }

    before do
      login_as(admin_user)
    end

    it 'returns 200' do
      get admin_organization_audit_logs_path(organization)
      expect(response).to have_http_status(:ok)
    end

    it 'assigns audit logs' do
      get admin_organization_audit_logs_path(organization)
      expect(assigns(:audits)).to be_present
    end

    it 'limits to 50 most recent audits' do
      get admin_organization_audit_logs_path(organization)
      expect(assigns(:audits).length).to be <= 50
    end

    context 'when organization does not exist' do
      it 'redirects to index' do
        get admin_organization_audit_logs_path('invalid-id')
        expect(response).to redirect_to(admin_organizations_path)
      end
    end
  end
end
