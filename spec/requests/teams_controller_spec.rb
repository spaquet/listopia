require 'rails_helper'

RSpec.describe TeamsController, type: :request do
  let(:user) { create(:user, :verified) }
  let(:organization) { create(:organization, creator: user) }

  before do
    create(:organization_membership, organization: organization, user: user, role: :owner)
  end

  def login_as(user)
    post session_path, params: { email: user.email, password: user.password }
  end

  describe 'authentication' do
    it 'requires user to be signed in for index' do
      get organization_teams_path(organization)
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for show' do
      team = create(:team, organization: organization)
      get organization_team_path(organization, team)
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for new' do
      get new_organization_team_path(organization)
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for create' do
      post organization_teams_path(organization), params: { team: { name: 'Test Team' } }
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for edit' do
      team = create(:team, organization: organization)
      get edit_organization_team_path(organization, team)
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for update' do
      team = create(:team, organization: organization)
      patch organization_team_path(organization, team), params: { team: { name: 'Updated' } }
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for destroy' do
      team = create(:team, organization: organization)
      delete organization_team_path(organization, team)
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe 'authorization' do
    let(:member_user) { create(:user, :verified) }

    before do
      create(:organization_membership, organization: organization, user: member_user, role: :member)
      login_as(member_user)
    end

    it 'denies non-owner from viewing teams index' do
      get organization_teams_path(organization)
      # Pundit redirects for HTML requests
      expect(response).to redirect_to(lists_path)
    end

    it 'denies non-owner from creating teams' do
      post organization_teams_path(organization), params: { team: { name: 'Test' } }
      # Pundit redirects for HTML requests
      expect(response).to redirect_to(lists_path)
    end
  end

  describe 'GET #index' do
    before { login_as(user) }

    it 'returns 200' do
      get organization_teams_path(organization)
      expect(response).to have_http_status(:ok)
    end

    it 'assigns teams' do
      team1 = create(:team, organization: organization)
      team2 = create(:team, organization: organization)

      get organization_teams_path(organization)

      expect(assigns(:teams)).to match_array([ team2, team1 ])
    end

    it 'orders teams by creation date (newest first)' do
      team1 = create(:team, organization: organization, created_at: 1.day.ago)
      team2 = create(:team, organization: organization)

      get organization_teams_path(organization)

      expect(assigns(:teams)).to eq([ team2, team1 ])
    end

    it 'does not include teams from other organizations' do
      other_org = create(:organization)
      other_team = create(:team, organization: other_org)

      get organization_teams_path(organization)

      expect(assigns(:teams)).not_to include(other_team)
    end
  end

  describe 'GET #show' do
    let(:team) { create(:team, organization: organization) }

    before do
      login_as(user)
      # User must be a team member to view
      org_membership = organization.organization_memberships.find_by(user: user)
      create(:team_membership, team: team, user: user, organization_membership: org_membership)
    end

    it 'returns 200' do
      get organization_team_path(organization, team)
      expect(response).to have_http_status(:ok)
    end

    it 'assigns the team' do
      get organization_team_path(organization, team)
      expect(assigns(:team)).to eq(team)
    end
  end

  describe 'GET #new' do
    before { login_as(user) }

    it 'returns 200' do
      get new_organization_team_path(organization)
      expect(response).to have_http_status(:ok)
    end

    it 'assigns a new team' do
      get new_organization_team_path(organization)
      expect(assigns(:team)).to be_a_new(Team)
    end

    it 'associates team with organization' do
      get new_organization_team_path(organization)
      expect(assigns(:team).organization).to eq(organization)
    end
  end

  describe 'POST #create' do
    before { login_as(user) }

    context 'with valid parameters' do
      it 'creates a new team' do
        expect {
          post organization_teams_path(organization),
               params: { team: { name: 'Engineering' } }
        }.to change(Team, :count).by(1)
      end

      it 'sets current user as creator' do
        post organization_teams_path(organization),
             params: { team: { name: 'Engineering' } }

        expect(Team.last.creator).to eq(user)
      end

      it 'associates team with organization' do
        post organization_teams_path(organization),
             params: { team: { name: 'Engineering' } }

        expect(Team.last.organization).to eq(organization)
      end

      it 'redirects to show' do
        post organization_teams_path(organization),
             params: { team: { name: 'Engineering' } }

        expect(response).to redirect_to(organization_team_path(organization, Team.last))
      end

      it 'displays success message' do
        post organization_teams_path(organization),
             params: { team: { name: 'Engineering' } }

        follow_redirect!
        expect(response.body).to include('Team created successfully')
      end
    end

    context 'with invalid parameters' do
      it 'does not create team with blank name' do
        expect {
          post organization_teams_path(organization),
               params: { team: { name: '' } }
        }.not_to change(Team, :count)
      end

      it 'returns 422 when name is blank' do
        post organization_teams_path(organization),
             params: { team: { name: '' } }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'renders new template on validation error' do
        post organization_teams_path(organization),
             params: { team: { name: '' } }

        expect(response.body).to include('Create Team')
      end
    end
  end

  describe 'GET #edit' do
    let(:team) { create(:team, organization: organization) }

    context 'when user is team admin' do
      before do
        login_as(user)
        # User must be team admin to edit
        org_membership = organization.organization_memberships.find_by(user: user)
        create(:team_membership, team: team, user: user, role: :admin, organization_membership: org_membership)
      end

      it 'returns 200' do
        get edit_organization_team_path(organization, team)
        expect(response).to have_http_status(:ok)
      end

      it 'assigns the team' do
        get edit_organization_team_path(organization, team)
        expect(assigns(:team)).to eq(team)
      end
    end

    context 'when user is not authorized' do
      let(:other_user) { create(:user, :verified) }

      before do
        create(:organization_membership, organization: organization, user: other_user, role: :member)
        login_as(other_user)
      end

      it 'denies access' do
        get edit_organization_team_path(organization, team)
        expect(response).to redirect_to(lists_path)
      end
    end
  end

  describe 'PATCH #update' do
    let(:team) { create(:team, organization: organization, name: 'Original Name') }

    before do
      login_as(user)
      # User must be team admin to update
      org_membership = organization.organization_memberships.find_by(user: user)
      create(:team_membership, team: team, user: user, role: :admin, organization_membership: org_membership)
    end

    context 'with valid parameters' do
      it 'updates the team' do
        patch organization_team_path(organization, team),
              params: { team: { name: 'Updated Name' } }

        expect(team.reload.name).to eq('Updated Name')
      end

      it 'redirects to show' do
        patch organization_team_path(organization, team),
              params: { team: { name: 'Updated Name' } }

        expect(response).to redirect_to(organization_team_path(organization, team))
      end

      it 'displays success message' do
        patch organization_team_path(organization, team),
              params: { team: { name: 'Updated Name' } }

        follow_redirect!
        expect(response.body).to include('Team updated successfully')
      end
    end

    context 'with invalid parameters' do
      it 'does not update team with blank name' do
        patch organization_team_path(organization, team),
              params: { team: { name: '' } }

        expect(team.reload.name).to eq('Original Name')
      end

      it 'returns 422 when name is blank' do
        patch organization_team_path(organization, team),
              params: { team: { name: '' } }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'renders edit template on validation error' do
        patch organization_team_path(organization, team),
              params: { team: { name: '' } }

        expect(response.body).to include('Edit')
      end
    end
  end

  describe 'DELETE #destroy' do
    let(:team) { create(:team, organization: organization) }

    before do
      login_as(user)
      # User must be team admin to destroy
      org_membership = organization.organization_memberships.find_by(user: user)
      create(:team_membership, team: team, user: user, role: :admin, organization_membership: org_membership)
    end

    context 'successful deletion' do
      it 'deletes the team' do
        team_id = team.id
        delete organization_team_path(organization, team)

        expect(Team.exists?(team_id)).to be false
      end

      it 'redirects to teams index' do
        delete organization_team_path(organization, team)

        expect(response).to redirect_to(organization_teams_path(organization))
      end

      it 'displays success message' do
        delete organization_team_path(organization, team)

        follow_redirect!
        expect(response.body).to include('Team deleted successfully')
      end
    end

    context 'when team cannot be deleted' do
      it 'handles deletion failure gracefully' do
        # Create a scenario where deletion might fail
        # (This would depend on actual validations in the model)
        allow_any_instance_of(Team).to receive(:destroy).and_return(false)

        delete organization_team_path(organization, team)

        expect(response).to redirect_to(organization_team_path(organization, team))
      end
    end
  end

  describe 'organization scoping' do
    let(:other_org) { create(:organization) }
    let(:other_team) { create(:team, organization: other_org) }

    before do
      login_as(user)
    end

    it 'does not allow updating team from different organization' do
      # User is not a member of the other organization
      patch organization_team_path(other_org, other_team),
            params: { team: { name: 'Hacked' } }

      # Policy check will deny access
      expect(response).to redirect_to(lists_path)
    end
  end
end
