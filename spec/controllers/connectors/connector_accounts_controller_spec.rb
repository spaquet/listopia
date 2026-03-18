require "rails_helper"

RSpec.describe Connectors::ConnectorAccountsController, type: :controller do
  before { sign_in user }

  let(:user) { create(:user) }
  let(:organization) { create(:organization, creator: user) }

  before do
    user.organizations << organization
    user.update!(current_organization_id: organization.id)
    Current.user = user
    Current.organization = organization
  end

  describe "GET #index" do
    it "returns a successful response" do
      get :index
      expect(response).to be_successful
    end

    it "assigns connectors and accounts" do
      account = create(:connectors_account, user: user, organization: organization)
      get :index
      expect(assigns(:accounts)).to include(account)
      expect(assigns(:connectors)).not_to be_empty
    end

    it "filters by provider if specified" do
      google = create(:connectors_account, user: user, organization: organization, provider: "google_calendar")
      slack = create(:connectors_account, user: user, organization: organization, provider: "slack")

      get :index, params: { provider: "google_calendar" }
      expect(assigns(:accounts)).to include(google)
      expect(assigns(:accounts)).not_to include(slack)
    end
  end

  describe "DELETE #destroy" do
    let(:account) { create(:connectors_account, user: user, organization: organization) }

    it "destroys the account" do
      expect {
        delete :destroy, params: { id: account.id }
      }.to change(Connectors::Account, :count).by(-1)
    end

    it "redirects to index" do
      delete :destroy, params: { id: account.id }
      expect(response).to redirect_to(connectors_connector_accounts_path)
    end
  end

  describe "POST #test" do
    let(:account) { create(:connectors_account, user: user, organization: organization) }

    before do
      allow_any_instance_of(Connectors::BaseConnector).to receive(:test_connection).and_return(true)
    end

    it "returns success JSON" do
      post :test, params: { id: account.id }, format: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["status"]).to eq("success")
    end
  end

  describe "PATCH #pause" do
    let(:account) { create(:connectors_account, user: user, organization: organization, status: "active") }

    it "pauses the account" do
      patch :pause, params: { id: account.id }
      expect(account.reload.status).to eq("paused")
    end
  end

  describe "PATCH #resume" do
    let(:account) { create(:connectors_account, user: user, organization: organization, status: "paused") }

    it "resumes the account" do
      patch :resume, params: { id: account.id }
      expect(account.reload.status).to eq("active")
    end
  end
end
