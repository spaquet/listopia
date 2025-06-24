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
      visit root_path
      # Use first sign up link (navigation) or be more specific
      first(:link, "Sign Up").click
      expect(page).to have_current_path(new_registration_path)
      expect(page).to have_content("Create your account")
    end

    it "can navigate to sign in page" do
      visit root_path
      # Use first sign in link (navigation) or be more specific
      first(:link, "Sign In").click
      expect(page).to have_current_path(new_session_path)
      expect(page).to have_content("Welcome back")
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
      page.driver.browser.manage.window.resize_to(375, 667) # iPhone size
      visit root_path
      expect(page).to have_content("Listopia")
    end

    it "renders properly on desktop viewport" do
      page.driver.browser.manage.window.resize_to(1920, 1080)
      visit root_path
      expect(page).to have_content("Listopia")
    end
  end
end
