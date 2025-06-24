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
    it { should have_many(:list_collaborations).dependent(:destroy) }
    it { should have_many(:collaborated_lists).through(:list_collaborations).source(:list) }
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
    it { should have_many(:list_collaborations).dependent(:destroy) }
    it { should have_many(:collaborators).through(:list_collaborations).source(:user) }
  end

  describe "ListItem model validations" do
    subject { build(:list_item) }

    it { should validate_presence_of(:title) }
    it { should validate_length_of(:title).is_at_most(255) }
    it { should validate_length_of(:description).is_at_most(1000) }
    it { should validate_presence_of(:item_type) }
    it { should validate_presence_of(:priority) }
  end

  describe "ListItem model associations" do
    subject { ListItem.new }

    it { should belong_to(:list) }
    it { should belong_to(:assigned_user).class_name('User').optional }
  end

  describe "ListCollaboration model associations" do
    subject { ListCollaboration.new }

    it { should belong_to(:list) }
    it { should belong_to(:user).optional }
  end

  describe "ListCollaboration model validations" do
    subject { build(:list_collaboration) }

    it { should validate_presence_of(:permission) }
  end

  describe "ListItem model enums" do
    it "defines item_type enum with correct values" do
      expect(ListItem.item_types).to eq({
        "task" => 0,
        "note" => 1,
        "link" => 2,
        "file" => 3,
        "reminder" => 4
      })
    end

    it "defines priority enum with correct values" do
      expect(ListItem.priorities).to eq({
        "low" => 0,
        "medium" => 1,
        "high" => 2,
        "urgent" => 3
      })
    end
  end

  describe "List model enums" do
    it "defines status enum with correct values" do
      expect(List.statuses).to eq({
        "draft" => 0,
        "active" => 1,
        "completed" => 2,
        "archived" => 3
      })
    end
  end

  describe "ListCollaboration model enums" do
    it "defines permission enum with correct values" do
      expect(ListCollaboration.permissions).to eq({
        "read" => 0,
        "collaborate" => 1
      })
    end
  end
end
