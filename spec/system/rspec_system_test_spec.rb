# spec/system/rspec_system_test_spec.rb
# This file tests that system/feature testing is working with Capybara

require 'rails_helper'

RSpec.describe "RSpec System Test Configuration", type: :system do
  describe "Capybara integration" do
    it "can load the home page" do
      visit root_path
      expect(page).to have_content("Listopia")
      expect(page).to have_content("Where Lists Come to Life")
    end

    it "can navigate to sign up page" do
      visit new_registration_path
      expect(page).to have_current_path(new_registration_path)
      # Check for form elements instead of hardcoded text
      expect(page).to have_field("Full name") rescue expect(page).to have_field("name")
    end

    it "can navigate to sign in page" do
      visit new_session_path
      expect(page).to have_current_path(new_session_path)
      # Check for form elements instead of hardcoded text
      expect(page).to have_field("email") rescue expect(page).to have_field("Email address")
    end
  end

  describe "JavaScript functionality" do
    it "handles JavaScript interactions", js: true do
      visit root_path
      # Test that JavaScript is enabled
      expect(page).to have_css("body")
      # You can add more JavaScript-specific tests here
    end
  end

  describe "Authentication flow" do
    let(:user) { create(:user, :verified) }

    it "can sign in a user through the UI" do
      visit new_session_path

      # Be more specific by targeting the main sign-in form
      within("form[action='#{session_path}']") do
        fill_in "Email address", with: user.email
        fill_in "Password", with: user.password
        click_button "Sign In"
      end

      expect(page).to have_current_path(dashboard_path)
      expect(page).to have_content("Welcome back!")
    end

    it "can sign up a new user through the UI" do
      visit new_registration_path

      fill_in "Full name", with: "Test User"
      fill_in "Email address", with: "test@example.com"
      fill_in "Password", with: "password123"
      fill_in "Confirm password", with: "password123"
      click_button "Create Account"

      expect(page).to have_current_path(verify_email_path)
      expect(page).to have_content("Please check your email")
    end
  end

  describe "Responsive design" do
    it "renders properly on mobile viewport" do
      # Cuprite uses evaluate_script for window resizing
      visit root_path
      page.driver.browser.evaluate("window.resizeTo(375, 667)")
      expect(page).to have_content("Listopia")
    end

    it "renders properly on desktop viewport" do
      visit root_path
      page.driver.browser.evaluate("window.resizeTo(1920, 1080)")
      expect(page).to have_content("Listopia")
    end
  end
end
