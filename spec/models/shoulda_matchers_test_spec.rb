# spec/models/shoulda_matchers_test_spec.rb
require 'rails_helper'

RSpec.describe "Shoulda Matchers Configuration", type: :model do
  describe "User model validations" do
    let!(:existing_user) { create(:user) }
    subject { build(:user) }

    it { should validate_presence_of(:email) }
    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:email) }
    it { should allow_value('user@example.com').for(:email) }
    it { should_not allow_value('invalid_email').for(:email) }
    it { should have_secure_password }
  end

  describe "User model associations" do
    subject { User.new }

    it { should have_many(:lists).dependent(:destroy) }
    it { should have_many(:collaborators).dependent(:destroy) }
    # Note: Polymorphic through association with source_type not fully supported by shoulda-matchers
    it { should have_many(:collaborated_lists).through(:collaborators).source(:collaboratable) }
    it { should have_many(:sessions).dependent(:destroy) }
  end

  describe "List model validations" do
    subject { build(:list) }

    it { should validate_presence_of(:title) }
    it { should validate_length_of(:title).is_at_most(255) }
    it { should validate_length_of(:description).is_at_most(1000) }
    it { should validate_presence_of(:status) }
  end

  describe "List model associations" do
    subject { List.new }

    it { should belong_to(:owner).class_name('User').with_foreign_key('user_id') }
    it { should have_many(:list_items).dependent(:destroy) }
    it { should have_many(:collaborators).dependent(:destroy) }
    it { should have_many(:collaborator_users).through(:collaborators).source(:user) }
  end

  describe "ListItem model validations" do
    subject { build(:list_item) }

    it { should validate_presence_of(:title) }
    it { should validate_length_of(:title).is_at_most(255) }
    # Note: description validation doesn't exist on ListItem model
    it { should validate_presence_of(:item_type) }
    it { should validate_presence_of(:priority) }
  end

  describe "ListItem model associations" do
    subject { ListItem.new }

    it { should belong_to(:list) }
    it { should belong_to(:assigned_user).class_name('User').optional }
  end

  describe "Collaborator model associations" do
    subject { Collaborator.new }

    it { should belong_to(:collaboratable) }
    it { should belong_to(:user) }
  end

  describe "Collaborator model validations" do
    subject { build(:collaborator) }

    it { should validate_presence_of(:permission) }
  end

  describe "ListItem model enums" do
    it "defines item_type enum with correct values" do
      expect(ListItem.item_types).to include("task", "note", "reminder", "meeting", "feature")
    end

    it "defines priority enum with correct values" do
      expect(ListItem.priorities).to include("low", "medium", "high", "urgent")
    end
  end

  describe "List model enums" do
    it "defines status enum with correct values" do
      expect(List.statuses).to include("draft", "active", "completed", "archived")
    end
  end

  describe "Collaborator model enums" do
    it "defines permission enum with correct values" do
      expect(Collaborator.permissions).to include("read", "write")
    end
  end
end
