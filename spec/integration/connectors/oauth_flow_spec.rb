require "rails_helper"

RSpec.describe "OAuth Flow", type: :system do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, creator: user) }

  before do
    user.organizations << organization
    user.update!(current_organization_id: organization.id)
    sign_in user
  end

  describe "Complete OAuth flow with Stub provider" do
    it "authorizes, exchanges code, and creates connected account" do
      # Step 1: User clicks "Connect" button, visits authorize action
      visit connectors_oauth_authorize_path("stub")

      expect(response).to have_http_status(:redirect)

      # Extract state from session (in real flow, user would go to provider)
      # For testing, we simulate the callback directly

      # Step 2: User is redirected back from OAuth provider with code
      state = session["oauth_state"]
      expect(state).to be_present

      visit connectors_oauth_callback_path("stub", code: "auth_code_123", state: state)

      # Step 3: User is redirected to settings page
      expect(response).to have_http_status(:redirect)
      follow_redirect!

      # Account should be created
      account = Connectors::Account.last
      expect(account).to be_present
      expect(account.user_id).to eq(user.id)
      expect(account.organization_id).to eq(organization.id)
      expect(account.provider).to eq("stub")
      expect(account.status).to eq("active")
      expect(account.access_token).to be_present
      expect(account.refresh_token).to be_present
    end

    it "shows error when state parameter is missing or invalid" do
      visit connectors_oauth_authorize_path("stub")
      state = session["oauth_state"]

      # Try callback without state
      visit connectors_oauth_callback_path("stub", code: "auth_code_123")

      expect(response).to have_http_status(:redirect)
      follow_redirect!
      expect(page).to have_text("Invalid OAuth state")
    end

    it "shows error when state parameter doesn't match" do
      visit connectors_oauth_authorize_path("stub")

      # Try callback with wrong state
      visit connectors_oauth_callback_path("stub", code: "auth_code_123", state: "wrong_state")

      expect(response).to have_http_status(:redirect)
      follow_redirect!
      expect(page).to have_text("Invalid OAuth state")
    end

    it "shows error when authorization code is invalid" do
      visit connectors_oauth_authorize_path("stub")
      state = session["oauth_state"]

      visit connectors_oauth_callback_path("stub", code: "invalid_code", state: state)

      expect(response).to have_http_status(:redirect)
      follow_redirect!
      expect(page).to have_text("Failed to connect account")
    end

    it "shows error when OAuth provider returns error" do
      visit connectors_oauth_authorize_path("stub")

      visit connectors_oauth_callback_path(
        "stub",
        error: "access_denied",
        error_description: "User denied access"
      )

      expect(response).to have_http_status(:redirect)
      follow_redirect!
      expect(page).to have_text("Authorization failed: User denied access")
    end
  end

  describe "Managing connected accounts" do
    let(:account) { create(:connectors_account, :with_tokens, user: user, organization: organization, provider: "stub") }

    before { account }

    it "displays connected accounts on dashboard" do
      visit connectors_connector_accounts_path

      expect(page).to have_text("My Connections")
      expect(page).to have_text(account.provider.titleize)
      expect(page).to have_text(account.display_name)
      expect(page).to have_text("Active")
    end

    it "allows user to view account settings" do
      visit connectors_setting_path(account)

      expect(page).to have_text("Stub Provider (Testing) Settings")
      expect(page).to have_text("Account Information")
      expect(page).to have_text("Connected As")
    end

    it "allows user to pause and resume account" do
      visit connectors_connector_accounts_path

      # Pause account
      click_link "Pause", match: :first
      expect(account.reload.status).to eq("paused")

      visit connectors_connector_accounts_path
      expect(page).to have_text("Paused")

      # Resume account
      click_link "Resume", match: :first
      expect(account.reload.status).to eq("active")
    end

    it "allows user to disconnect account" do
      visit connectors_connector_accounts_path

      click_link "Disconnect"

      expect(Connectors::Account.find_by(id: account.id)).to be_nil
    end

    it "allows user to test connection" do
      visit connectors_connector_accounts_path

      # Make API call (in real scenario, this would hit real API)
      page.execute_script("fetch('#{connectors_test_connector_account_path(account)}', {method: 'POST'})")

      # Would return status in response
      expect(response).to have_http_status(:success)
    end
  end

  describe "Token refresh job" do
    let(:account) do
      create(:connectors_account,
        :with_tokens,
        user: user,
        organization: organization,
        provider: "stub",
        token_expires_at: 30.minutes.from_now)
    end

    it "refreshes token before expiration" do
      old_access_token = account.access_token

      # Trigger token refresh job
      Connectors::TokenRefreshJob.perform_now(connector_account_id: account.id)

      account.reload
      expect(account.access_token).not_to eq(old_access_token)
      expect(account.token_expires_at).to be_within(2.seconds).of(1.hour.from_now)
    end

    it "skips refresh if token expiry is more than 1 hour away" do
      account.update!(token_expires_at: 2.hours.from_now)
      old_access_token = account.access_token

      Connectors::TokenRefreshJob.perform_now(connector_account_id: account.id)

      # Token should not be refreshed
      expect(account.reload.access_token).to eq(old_access_token)
    end

    it "handles refresh errors gracefully" do
      account.update!(refresh_token_encrypted: nil)

      # Should not raise error
      expect {
        Connectors::TokenRefreshJob.perform_now(connector_account_id: account.id)
      }.not_to raise_error
    end
  end
end
