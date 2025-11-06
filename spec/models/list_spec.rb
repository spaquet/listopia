require 'rails_helper'

RSpec.describe List, type: :model do
  describe 'associations' do
    it { should belong_to(:owner).class_name('User').with_foreign_key('user_id') }
    it { should have_many(:list_items).dependent(:destroy) }
    it { should have_many(:board_columns).dependent(:destroy) }
    it { should have_many(:collaborators).dependent(:destroy) }
    it { should have_many(:collaborator_users).through(:collaborators).source(:user) }
    it { should have_many(:invitations).dependent(:destroy) }
    it { should have_many(:comments).dependent(:destroy) }
    it { should have_many(:parent_relationships).dependent(:destroy) }
    it { should have_many(:child_relationships).dependent(:destroy) }
    it { should belong_to(:parent_list).class_name('List').optional }
    it { should have_many(:sub_lists).class_name('List').with_foreign_key('parent_list_id').dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:list) }

    it { should validate_presence_of(:title) }
    it { should validate_length_of(:title).is_at_most(255) }
    it { should validate_length_of(:description).is_at_most(1000) }
    it { should validate_presence_of(:status) }
  end

  describe 'scopes' do
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }

    describe '.active' do
      it 'returns only active lists' do
        active_list = create(:list, :active, owner: user)
        create(:list, :draft, owner: user)
        create(:list, :archived, owner: user)

        expect(List.active).to contain_exactly(active_list)
      end
    end

    describe '.recent' do
      it 'returns lists ordered by most recently updated' do
        old_list = create(:list, owner: user)
        Timecop.freeze(Time.current + 1.hour) do
          new_list = create(:list, owner: user)
          expect(List.recent.first).to eq(new_list)
          expect(List.recent.last).to eq(old_list)
        end
      end
    end

    describe '.parent_lists' do
      it 'returns only lists without a parent' do
        parent = create(:list, owner: user, parent_list: nil)
        child = create(:list, owner: user, parent_list: parent)

        expect(List.parent_lists).to contain_exactly(parent)
        expect(List.parent_lists).not_to include(child)
      end
    end

    describe '.sub_lists' do
      it 'returns only lists with a parent' do
        parent = create(:list, owner: user)
        child = create(:list, owner: user, parent_list: parent)

        expect(List.sub_lists).to contain_exactly(child)
        expect(List.sub_lists).not_to include(parent)
      end
    end
  end

  describe '#readable_by?' do
    let(:owner) { create(:user) }
    let(:other_user) { create(:user) }
    let(:list) { create(:list, owner: owner) }

    context 'with private list' do
      it 'is readable by owner' do
        expect(list.readable_by?(owner)).to be true
      end

      it 'is not readable by other users' do
        expect(list.readable_by?(other_user)).to be false
      end

      it 'returns false for nil user' do
        expect(list.readable_by?(nil)).to be false
      end
    end

    context 'with public list' do
      before { list.update!(is_public: true) }

      it 'is readable by any user' do
        expect(list.readable_by?(other_user)).to be true
      end
    end
  end

  describe '#writable_by?' do
    let(:owner) { create(:user) }
    let(:other_user) { create(:user) }
    let(:list) { create(:list, owner: owner) }

    context 'with private list' do
      it 'is writable by owner' do
        expect(list.writable_by?(owner)).to be true
      end

      it 'is not writable by other users' do
        expect(list.writable_by?(other_user)).to be false
      end

      it 'returns false for nil user' do
        expect(list.writable_by?(nil)).to be false
      end
    end

    context 'with public writable list' do
      before do
        list.update!(is_public: true, public_permission: :public_write)
      end

      it 'is writable by owner' do
        expect(list.writable_by?(owner)).to be true
      end

      it 'is writable by any user' do
        expect(list.writable_by?(other_user)).to be true
      end
    end
  end

  describe 'callbacks' do
    describe '#generate_public_slug' do
      it 'generates slug when list is created as public' do
        list = create(:list, :public)
        expect(list.public_slug).to be_present
      end

      it 'does not generate slug for private list' do
        list = create(:list, is_public: false)
        expect(list.public_slug).to be_nil
      end

      it 'generates unique slugs' do
        list1 = create(:list, :public, title: "Test List")
        list2 = create(:list, :public, title: "Test List")

        expect(list1.public_slug).not_to eq(list2.public_slug)
      end
    end

    describe '#create_default_board_columns' do
      it 'creates default board columns when list is created' do
        list = create(:list)
        expect(list.board_columns.count).to be > 0
      end
    end
  end

  describe 'hierarchy relationships' do
    let(:owner) { create(:user) }

    it 'has parent-child relationships' do
      parent_list = create(:list, owner: owner)
      child_list = create(:list, owner: owner, parent_list: parent_list)
      
      expect(child_list.parent_list).to eq(parent_list)
      expect(parent_list.sub_lists).to include(child_list)
    end
  end

  describe 'metadata' do
    let(:list) { create(:list) }

    it 'stores arbitrary metadata' do
      list.update(metadata: { custom_key: "custom_value" })
      expect(list.metadata["custom_key"]).to eq("custom_value")
    end

    it 'defaults to empty hash' do
      expect(list.metadata).to eq({})
    end
  end

  describe 'color themes' do
    it 'stores color theme' do
      list = create(:list, color_theme: "red")
      expect(list.color_theme).to eq("red")
    end
  end
end
