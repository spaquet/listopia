# spec/models/list_spec.rb
require 'rails_helper'

RSpec.describe List, type: :model do
  let(:user) { create(:user, :verified) }
  let(:list) { create(:list, owner: user) }

  describe 'validations' do
    subject { build(:list) }

    it { should validate_presence_of(:title) }
    it { should validate_length_of(:title).is_at_most(255) }
    it { should validate_length_of(:description).is_at_most(1000) }
    it { should validate_presence_of(:status) }

    context 'title validation' do
      it 'accepts valid titles' do
        valid_titles = [
          'My List',
          'Shopping List for Vacation',
          'Project Tasks - Q4 2024',
          'A' * 255  # Maximum length
        ]

        valid_titles.each do |title|
          expect(build(:list, title: title)).to be_valid
        end
      end

      it 'rejects empty titles' do
        expect(build(:list, title: '')).not_to be_valid
        expect(build(:list, title: nil)).not_to be_valid
        expect(build(:list, title: '   ')).not_to be_valid
      end

      it 'rejects titles that are too long' do
        long_title = 'A' * 256
        expect(build(:list, title: long_title)).not_to be_valid
      end
    end

    context 'description validation' do
      it 'accepts empty descriptions' do
        expect(build(:list, description: nil)).to be_valid
        expect(build(:list, description: '')).to be_valid
      end

      it 'accepts valid descriptions' do
        description = 'A' * 1000  # Maximum length
        expect(build(:list, description: description)).to be_valid
      end

      it 'rejects descriptions that are too long' do
        long_description = 'A' * 1001
        expect(build(:list, description: long_description)).not_to be_valid
      end
    end
  end

  describe 'associations' do
    it { should belong_to(:owner).class_name('User').with_foreign_key('user_id') }
    it { should have_many(:list_items).dependent(:destroy) }
    it { should have_many(:list_collaborations).dependent(:destroy) }
    it { should have_many(:collaborators).through(:list_collaborations).source(:user) }
  end

  describe 'enums' do
    it 'defines status enum correctly' do
      expect(List.statuses).to eq({
        'draft' => 0,
        'active' => 1,
        'completed' => 2,
        'archived' => 3
      })
    end

    it 'allows setting status using enum methods' do
      list = create(:list, :draft)
      expect(list.status_draft?).to be true

      list.status_active!
      expect(list.status_active?).to be true
      expect(list.status_draft?).to be false
    end
  end

  describe 'scopes' do
    let!(:active_list) { create(:list, :active, owner: user) }
    let!(:draft_list) { create(:list, :draft, owner: user) }
    let!(:completed_list) { create(:list, :completed, owner: user) }
    let!(:other_user_list) { create(:list, :active) }

    describe '.active' do
      it 'returns only active lists' do
        expect(List.active).to contain_exactly(active_list, other_user_list)
      end
    end

    describe '.owned_by' do
      it 'returns lists owned by specific user' do
        owned_lists = List.owned_by(user)
        expect(owned_lists).to contain_exactly(active_list, draft_list, completed_list)
      end
    end

    describe '.accessible_by' do
      let(:collaborator) { create(:user, :verified) }
      let!(:collaboration) { create(:list_collaboration, list: active_list, user: collaborator) }

      it 'returns lists owned by user' do
        accessible = List.accessible_by(user).to_a
        expect(accessible).to include(active_list, draft_list, completed_list)
      end

      it 'returns lists where user is a collaborator' do
        accessible = List.accessible_by(collaborator).to_a
        expect(accessible).to include(active_list)
      end

      it 'does not return lists where user has no access' do
        accessible = List.accessible_by(collaborator).to_a
        expect(accessible).not_to include(draft_list, completed_list, other_user_list)
      end
    end
  end

  describe 'callbacks' do
    describe 'generate_public_slug' do
      it 'generates slug when is_public is true and slug is blank' do
        list = build(:list, is_public: true, public_slug: nil)
        list.save!

        expect(list.public_slug).to be_present
        expect(list.public_slug.length).to be >= 8
      end

      it 'does not overwrite existing slug' do
        existing_slug = 'custom-slug'
        list = build(:list, is_public: true, public_slug: existing_slug)
        list.save!

        expect(list.public_slug).to eq(existing_slug)
      end

      it 'does not generate slug when is_public is false' do
        list = build(:list, is_public: false)
        list.save!

        expect(list.public_slug).to be_nil
      end
    end
  end

  describe 'access control methods' do
    let(:owner) { create(:user, :verified) }
    let(:collaborator_read) { create(:user, :verified) }
    let(:collaborator_write) { create(:user, :verified) }
    let(:non_collaborator) { create(:user, :verified) }
    let(:list) { create(:list, owner: owner) }

    before do
      create(:list_collaboration, :read_permission, list: list, user: collaborator_read)
      create(:list_collaboration, :collaborate_permission, list: list, user: collaborator_write)
    end

    describe '#readable_by?' do
      it 'returns true for owner' do
        expect(list.readable_by?(owner)).to be true
      end

      it 'returns true for read collaborator' do
        expect(list.readable_by?(collaborator_read)).to be true
      end

      it 'returns true for write collaborator' do
        expect(list.readable_by?(collaborator_write)).to be true
      end

      it 'returns false for non-collaborator on private list' do
        expect(list.readable_by?(non_collaborator)).to be false
      end

      it 'returns true for non-collaborator on public list' do
        list.update!(is_public: true)
        expect(list.readable_by?(non_collaborator)).to be true
      end

      it 'returns false for nil user' do
        expect(list.readable_by?(nil)).to be false
      end
    end

    describe '#collaboratable_by?' do
      it 'returns true for owner' do
        expect(list.collaboratable_by?(owner)).to be true
      end

      it 'returns false for read-only collaborator' do
        expect(list.collaboratable_by?(collaborator_read)).to be false
      end

      it 'returns true for write collaborator' do
        expect(list.collaboratable_by?(collaborator_write)).to be true
      end

      it 'returns false for non-collaborator' do
        expect(list.collaboratable_by?(non_collaborator)).to be false
      end

      it 'returns false for nil user' do
        expect(list.collaboratable_by?(nil)).to be false
      end
    end
  end

  describe 'collaboration management' do
    let(:collaborator) { create(:user, :verified) }

    describe '#add_collaborator' do
      it 'adds collaborator with default read permission' do
        collaboration = list.add_collaborator(collaborator)

        expect(collaboration).to be_persisted
        expect(collaboration.user).to eq(collaborator)
        expect(collaboration.permission).to eq('read')
      end

      it 'adds collaborator with specified permission' do
        collaboration = list.add_collaborator(collaborator, permission: 'collaborate')

        expect(collaboration.permission).to eq('collaborate')
      end

      it 'updates existing collaboration instead of creating duplicate' do
        existing = create(:list_collaboration, list: list, user: collaborator, permission: 'read')

        expect {
          result = list.add_collaborator(collaborator, permission: 'collaborate')
          expect(result).to eq(existing) # The method should return the updated existing collaboration
        }.not_to change { list.list_collaborations.count }

        expect(existing.reload.permission).to eq('collaborate')
      end
    end

    describe '#remove_collaborator' do
      let!(:collaboration) { create(:list_collaboration, list: list, user: collaborator) }

      it 'removes existing collaborator' do
        expect {
          list.remove_collaborator(collaborator)
        }.to change { list.list_collaborations.count }.by(-1)
      end

      it 'does nothing if user is not a collaborator' do
        other_user = create(:user, :verified)

        expect {
          list.remove_collaborator(other_user)
        }.not_to change { list.list_collaborations.count }
      end
    end
  end

  describe '#completion_percentage' do
    context 'with no items' do
      it 'returns 0' do
        expect(list.completion_percentage).to eq(0)
      end
    end

    context 'with items' do
      before do
        create_list(:list_item, 2, :completed, list: list)
        create_list(:list_item, 3, :pending, list: list)
      end

      it 'calculates percentage correctly' do
        # 2 completed out of 5 total = 40%
        expect(list.completion_percentage).to eq(40.0)
      end

      it 'returns 100% when all items are completed' do
        list.list_items.pending.update_all(completed: true)
        expect(list.completion_percentage).to eq(100.0)
      end

      it 'returns 0% when no items are completed' do
        list.list_items.completed.update_all(completed: false)
        expect(list.completion_percentage).to eq(0.0)
      end

      it 'rounds to 2 decimal places' do
        # Create scenario where result is not a round number
        list.list_items.destroy_all
        create(:list_item, :completed, list: list)
        create_list(:list_item, 2, :pending, list: list)

        # 1 out of 3 = 33.333...%
        expect(list.reload.completion_percentage).to eq(33.33)
      end
    end
  end

  describe 'public list functionality' do
    describe 'public slug generation' do
      it 'generates unique slugs for public lists' do
        list1 = create(:list, :public)
        list2 = create(:list, :public)

        expect(list1.public_slug).to be_present
        expect(list2.public_slug).to be_present
        expect(list1.public_slug).not_to eq(list2.public_slug)
      end

      it 'uses URL-safe characters in slug' do
        list = create(:list, :public)

        expect(list.public_slug).to match(/\A[A-Za-z0-9_-]+\z/)
      end
    end
  end

  describe 'UUID primary key' do
    it 'uses UUID as primary key' do
      expect(list.id).to be_present
      expect(list.id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it 'generates unique UUIDs' do
      list1 = create(:list)
      list2 = create(:list)

      expect(list1.id).not_to eq(list2.id)
    end
  end

  describe 'metadata handling' do
    it 'accepts JSON metadata' do
      metadata = { 'color' => 'blue', 'tags' => [ 'work', 'important' ] }
      list = create(:list, metadata: metadata)

      expect(list.metadata).to eq(metadata)
    end

    it 'handles nil metadata' do
      list = create(:list, metadata: nil)
      expect(list.metadata).to be_nil
    end
  end
end
