# spec/factories_spec.rb
# This file tests that all FactoryBot factories are valid

require 'rails_helper'

RSpec.describe "FactoryBot factories" do
  describe "factory validity" do
    it "has valid factories" do
      # This will test all factories and their traits
      FactoryBot.lint
    end
  end

  describe "individual factory testing" do
    describe "User factory" do
      it "creates valid users" do
        expect(build(:user)).to be_valid
        expect(build(:user, :verified)).to be_valid
        expect(build(:user, :unverified)).to be_valid
        expect(build(:user, :with_bio)).to be_valid
        expect(build(:user, :with_avatar)).to be_valid
      end

      it "creates unique emails" do
        user1 = create(:user)
        user2 = create(:user)
        expect(user1.email).not_to eq(user2.email)
      end
    end

    describe "List factory" do
      it "creates valid lists" do
        expect(build(:list)).to be_valid
        expect(build(:list, :draft)).to be_valid
        expect(build(:list, :active)).to be_valid
        expect(build(:list, :completed)).to be_valid
        expect(build(:list, :archived)).to be_valid
        expect(build(:list, :public)).to be_valid
      end

      it "creates lists with associations" do
        list = create(:list, :with_items)
        expect(list.list_items.count).to eq(3)
        expect(list.owner).to be_present
      end

      it "creates public lists with slugs" do
        list = create(:list, :public)
        expect(list.is_public?).to be true
        expect(list.public_slug).to be_present
      end
    end

    describe "ListItem factory" do
      it "creates valid list items" do
        expect(build(:list_item)).to be_valid
        expect(build(:list_item, :task)).to be_valid
        expect(build(:list_item, :note)).to be_valid
        expect(build(:list_item, :link)).to be_valid
        expect(build(:list_item, :reminder)).to be_valid
      end

      it "creates items with different priorities" do
        low_item = create(:list_item, :low_priority)
        high_item = create(:list_item, :high_priority)

        expect(low_item.priority_low?).to be true
        expect(high_item.priority_high?).to be true
      end

      it "creates completed items with timestamps" do
        item = create(:list_item, :completed)
        expect(item.completed?).to be true
        expect(item.status_changed_at).to be_present
      end

      it "creates overdue items" do
        item = create(:list_item, :overdue)
        expect(item.overdue?).to be true
      end
    end
  end
end
