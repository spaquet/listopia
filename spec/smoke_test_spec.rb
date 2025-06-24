# spec/smoke_test_spec.rb
# This file tests that RSpec configuration is working properly

require 'rails_helper'

RSpec.describe "RSpec Configuration Smoke Test", type: :request do
  describe "Basic RSpec functionality" do
    it "can run a simple test" do
      expect(true).to be true
    end

    it "can access Rails environment" do
      expect(Rails.env).to eq('test')
    end

    it "can connect to test database" do
      expect(ActiveRecord::Base.connection).to be_present
    end
  end

  describe "FactoryBot integration" do
    it "can create a user factory" do
      user = build(:user)
      expect(user).to be_a(User)
      expect(user.email).to be_present
      expect(user.name).to be_present
    end

    it "can create and save a user" do
      user = create(:user, :verified)
      expect(user).to be_persisted
      expect(user.email_verified?).to be true
    end

    it "can create a list with items" do
      list = create(:list, :with_items)
      expect(list.list_items.count).to eq(3)
    end
  end

  describe "Authentication helpers" do
    it "can sign in a user (simulation)" do
      user = create(:user, :verified)
      # Simulate session-based sign in for request specs
      post session_path, params: { email: user.email, password: user.password }
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "Request helpers" do
    it "can parse JSON responses" do
      # Create a simple JSON endpoint test
      user = create(:user, :verified)
      # This would work if we had a JSON API endpoint
      # For now, just test the helper method exists
      expect(self).to respond_to(:json_response)
    end

    it "can test flash messages" do
      expect(self).to respond_to(:expect_flash)
    end

    it "can test Turbo Stream responses" do
      expect(self).to respond_to(:expect_turbo_stream_response)
    end
  end

  describe "Database cleaning" do
    it "starts with a clean database" do
      initial_user_count = User.count
      create(:user)
      expect(User.count).to eq(initial_user_count + 1)
    end

    it "cleans database between tests" do
      # This test should start fresh (proving database cleaning works)
      expect(User.count).to eq(0) # Should be 0 if database_cleaner is working
    end
  end

  describe "Shoulda matchers", type: :model do
    describe "User validations" do
      # Use a saved user instance for uniqueness testing
      let!(:existing_user) { create(:user) }
      subject { build(:user) }

      it "validates presence of email" do
        expect(subject).to validate_presence_of(:email)
      end

      it "validates presence of name" do
        expect(subject).to validate_presence_of(:name)
      end

      it "validates uniqueness of email" do
        expect(subject).to validate_uniqueness_of(:email)
      end

      it "validates email format" do
        expect(subject).to allow_value('user@example.com').for(:email)
        expect(subject).not_to allow_value('invalid_email').for(:email)
      end
    end

    it "can use association matchers" do
      expect(User.new).to have_many(:lists).dependent(:destroy)
      expect(User.new).to have_many(:list_collaborations).dependent(:destroy)
      expect(List.new).to belong_to(:owner).class_name('User')
      expect(ListItem.new).to belong_to(:list)
    end
  end

  describe "Rails 8 specific features" do
    it "can test token generation (Rails 8 feature)" do
      user = create(:user, :verified)
      token = user.generate_magic_link_token
      expect(token).to be_present
      expect(token).to be_a(String)
    end

    it "can find user by magic link token" do
      user = create(:user, :verified)
      token = user.generate_magic_link_token
      found_user = User.find_by_magic_link_token(token)
      expect(found_user).to eq(user)
    end
  end

  describe "Enum testing" do
    it "can test list status enums" do
      list = create(:list, :active)
      expect(list.status_active?).to be true
      expect(list.status_draft?).to be false

      list.status_completed!
      expect(list.status_completed?).to be true
    end

    it "can test list item priority enums" do
      item = create(:list_item, :high_priority)
      expect(item.priority_high?).to be true
      expect(item.priority_low?).to be false
    end
  end
end
