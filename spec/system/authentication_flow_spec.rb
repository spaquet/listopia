# spec/system/authentication_flow_spec.rb
require 'rails_helper'

RSpec.describe "Authentication Flow", type: :system do
  let(:user) { create(:user, :verified) }

  describe "Sign in process" do
    it "allows user to sign in with valid credentials" do
      visit new_session_path

      # Use CSS selectors to be more specific
      find('input[name="email"]').set(user.email)
      find('input[name="password"]').set(user.password)
      find('input[type="submit"][value="Sign In"]').click

      expect(page).to have_current_path(dashboard_path)
      expect(page).to have_content("Welcome back!")
    end

    it "shows error for invalid credentials" do
      visit new_session_path

      find('input[name="email"]').set(user.email)
      find('input[name="password"]').set("wrong_password")
      find('input[type="submit"][value="Sign In"]').click

      expect(page).to have_current_path(new_session_path)
      expect(page).to have_content("Invalid email or password")
    end
  end

  describe "Sign up process" do
    it "allows new user registration" do
      visit new_registration_path

      within("form[action='#{registration_path}']") do
        fill_in "Full name", with: "Test User"
        fill_in "Email address", with: "newuser@example.com"
        fill_in "Password", with: "password123"
        fill_in "Confirm password", with: "password123"
        click_button "Create Account"
      end

      expect(page).to have_current_path(verify_email_path)
      expect(page).to have_content("Please check your email")
    end
  end

  describe "Magic link authentication" do
    it "shows magic link form" do
      visit new_session_path

      # Test that magic link section exists
      expect(page).to have_content("Or")
      expect(page).to have_button("Send Magic Link")
    end

    it "can request magic link" do
      visit new_session_path

      # Use the magic link form specifically
      within("form[action='#{magic_link_path}']") do
        fill_in placeholder: "Enter your email for magic link", with: user.email
        click_button "Send Magic Link"
      end

      expect(page).to have_current_path(magic_link_sent_path)
      expect(page).to have_content("Check your email")
    end
  end
end
