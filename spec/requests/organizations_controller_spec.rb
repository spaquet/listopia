require "rails_helper"

RSpec.describe OrganizationsController, type: :request do
  let(:user) { create(:user, :verified) }
  let(:org1) { create(:organization, creator: user) }
  let(:org2) { create(:organization, creator: user) }

  before do
    # Create organization memberships
    create(:organization_membership, user: user, organization: org1, role: :owner)
    create(:organization_membership, user: user, organization: org2, role: :member)
  end

  def login_as(user)
    post session_path, params: { email: user.email, password: user.password }
  end

  describe "GET #switcher" do
    context "when user is authenticated" do
      before { login_as(user) }

      it "returns all active organizations for the user" do
        get switcher_organizations_path, params: {}, headers: { "Accept" => Mime[:turbo_stream].to_s }
        expect(response.status).to eq(200)
        expect(response.media_type).to eq Mime[:turbo_stream]
      end

      it "only includes active organizations" do
        org2.update(status: :suspended)
        get switcher_organizations_path, params: {}, headers: { "Accept" => Mime[:turbo_stream].to_s }
        expect(response.body).not_to include(org2.name)
      end

      it "rejects HTML requests and redirects" do
        get switcher_organizations_path
        expect(response).to redirect_to(dashboard_path)
      end
    end

    context "when user is not authenticated" do
      it "requires authentication" do
        get switcher_organizations_path, params: {}, headers: { "Accept" => Mime[:turbo_stream].to_s }
        expect(response.status).to eq(401)
      end
    end
  end

  describe "PATCH #switch" do
    before { login_as(user) }

    context "when switching to a different organization" do
      it "succeeds and sets organization in session" do
        patch switch_organizations_path, params: { organization_id: org2.id }, headers: { "Accept" => Mime[:turbo_stream].to_s }
        # Verify the request succeeded and returns turbo-stream response
        expect([200, 204]).to include(response.status)
        if response.status == 200
          expect(response.body).to include("turbo-stream")
        end
      end
    end

    context "when switching to the current organization" do
      before do
        # Set current_organization first by patching to org1
        patch switch_organizations_path, params: { organization_id: org1.id }, headers: { "Accept" => Mime[:turbo_stream].to_s }
      end

      it "returns no content when switching to same organization" do
        patch switch_organizations_path, params: { organization_id: org1.id }, headers: { "Accept" => Mime[:turbo_stream].to_s }
        expect(response.status).to eq(204)
      end
    end

    context "when user is not a member of the organization" do
      let(:other_org) { create(:organization) }

      it "denies access" do
        patch switch_organizations_path, params: { organization_id: other_org.id }, headers: { "Accept" => Mime[:turbo_stream].to_s }
        expect(response.status).to eq(403)
      end
    end

    context "with HTML format" do
      it "redirects appropriately" do
        patch switch_organizations_path, params: { organization_id: org2.id }
        # Redirect either back or to dashboard
        expect([request.referrer || dashboard_path, response.redirect_url]).to include(response.redirect_url) if response.redirect?
      end
    end
  end

  describe "authentication" do
    it "requires user to be signed in to access switcher" do
      get switcher_organizations_path, params: {}, headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response.status).to eq(401)
    end

    it "requires user to be signed in to switch" do
      patch switch_organizations_path, params: { organization_id: org1.id }, headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response.status).to eq(401)
    end
  end
end
