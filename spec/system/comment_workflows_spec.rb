# spec/system/comment_workflows_spec.rb
require 'rails_helper'

RSpec.describe "Comment Workflows", type: :system, js: true do
  let(:owner) { FactoryBot.create(:user, :verified) }
  let(:list) { FactoryBot.create(:list, owner: owner) }

  it "user adds a comment to a List and sees it immediately" do
    # Sign in via the login form
    visit new_session_path

    # The form uses form_with with no model, so fields are :email and :password
    fill_in 'email', with: owner.email
    fill_in 'password', with: owner.password
    click_button "Sign In"

    # Navigate to the list
    visit list_path(list)

    # Wait for page to load
    expect(page).to have_text(list.title)

    # Find and fill the comment textarea using its placeholder
    fill_in 'comment[content]', with: "This is my first comment!"
    click_button "Comment"

    # Verify the comment appears
    expect(page).to have_text("This is my first comment!", wait: 5)
    expect(page).to have_text(owner.name)
  end
end
