# spec/models/list_item_spec.rb
require 'rails_helper'

RSpec.describe ListItem, type: :model do
  let(:list) { create(:list) }
  let(:list_item) { create(:list_item, list: list) }

  describe 'validations' do
    subject { build(:list_item) }

    it { should validate_presence_of(:title) }
    it { should validate_length_of(:title).is_at_most(255) }
    it { should validate_length_of(:description).is_at_most(1000) }
    it { should validate_presence_of(:item_type) }
    it { should validate_presence_of(:priority) }

    context 'title validation' do
      it 'accepts valid titles' do
        valid_titles = [
          'Buy groceries',
          'Complete project proposal',
          'Call client about meeting',
          'A' * 255  # Maximum length
        ]

        valid_titles.each do |title|
          expect(build(:list_item, title: title)).to be_valid
        end
      end

      it 'rejects empty titles' do
        expect(build(:list_item, title: '')).not_to be_valid
        expect(build(:list_item, title: nil)).not_to be_valid
        expect(build(:list_item, title: '   ')).not_to be_valid
      end

      it 'rejects titles that are too long' do
        long_title = 'A' * 256
        expect(build(:list_item, title: long_title)).not_to be_valid
      end
    end

    context 'description validation' do
      it 'accepts empty descriptions' do
        expect(build(:list_item, description: nil)).to be_valid
        expect(build(:list_item, description: '')).to be_valid
      end

      it 'accepts valid descriptions' do
        description = 'A' * 1000  # Maximum length
        expect(build(:list_item, description: description)).to be_valid
      end

      it 'rejects descriptions that are too long' do
        long_description = 'A' * 1001
        expect(build(:list_item, description: long_description)).not_to be_valid
      end
    end
  end

  describe 'associations' do
    it { should belong_to(:list) }
    it { should belong_to(:assigned_user).class_name('User').optional }
  end

  describe 'enums' do
    describe 'item_type enum' do
      it 'defines item_type enum correctly' do
        expect(ListItem.item_types).to eq({
          'task' => 0,
          'note' => 1,
          'link' => 2,
          'file' => 3,
          'reminder' => 4
        })
      end

      it 'allows setting item_type using enum methods' do
        item = create(:list_item, :task)
        expect(item.item_type_task?).to be true

        item.item_type_note!
        expect(item.item_type_note?).to be true
        expect(item.item_type_task?).to be false
      end
    end

    describe 'priority enum' do
      it 'defines priority enum correctly' do
        expect(ListItem.priorities).to eq({
          'low' => 0,
          'medium' => 1,
          'high' => 2,
          'urgent' => 3
        })
      end

      it 'allows setting priority using enum methods' do
        item = create(:list_item, :medium_priority)
        expect(item.priority_medium?).to be true

        item.priority_high!
        expect(item.priority_high?).to be true
        expect(item.priority_medium?).to be false
      end
    end
  end

  describe 'scopes' do
    let!(:completed_item) { create(:list_item, :completed, list: list) }
    let!(:pending_item) { create(:list_item, :pending, list: list) }
    let!(:high_priority_item) { create(:list_item, :high_priority, list: list) }
    let!(:low_priority_item) { create(:list_item, :low_priority, list: list) }
    let!(:assigned_item) { create(:list_item, :with_assignment, list: list) }
    let!(:old_item) { create(:list_item, list: list, created_at: 1.week.ago) }

    describe '.completed' do
      it 'returns only completed items' do
        expect(ListItem.completed).to contain_exactly(completed_item)
      end
    end

    describe '.pending' do
      it 'returns only pending items' do
        pending_items = ListItem.pending
        expect(pending_items).to include(pending_item, high_priority_item, low_priority_item, assigned_item, old_item)
        expect(pending_items).not_to include(completed_item)
      end
    end

    describe '.assigned_to' do
      it 'returns items assigned to specific user' do
        user = assigned_item.assigned_user
        expect(ListItem.assigned_to(user)).to contain_exactly(assigned_item)
      end
    end

    describe '.by_priority' do
      it 'orders items by priority (low to urgent)' do
        items = ListItem.by_priority.where(list: list)
        priorities = items.pluck(:priority)

        # Should be ordered by enum value: low(0), medium(1), high(2), urgent(3)
        expect(priorities).to eq(priorities.sort)
      end
    end

    describe '.recent' do
      it 'orders items by created_at descending' do
        items = ListItem.recent.where(list: list).limit(2)

        expect(items.first.created_at).to be >= items.second.created_at
      end
    end
  end

  describe 'completion tracking' do
    describe '#toggle_completion!' do
      context 'when item is pending' do
        let(:pending_item) { create(:list_item, :pending) }

        it 'marks item as completed' do
          expect {
            pending_item.toggle_completion!
          }.to change { pending_item.completed? }.from(false).to(true)
        end

        it 'sets completed_at timestamp' do
          travel_to Time.current do
            pending_item.toggle_completion!
            expect(pending_item.completed_at).to be_within(1.second).of(Time.current)
          end
        end
      end

      context 'when item is completed' do
        let(:completed_item) { create(:list_item, :completed) }

        it 'marks item as pending' do
          expect {
            completed_item.toggle_completion!
          }.to change { completed_item.completed? }.from(true).to(false)
        end

        it 'clears completed_at timestamp' do
          completed_item.toggle_completion!
          expect(completed_item.completed_at).to be_nil
        end
      end
    end

    describe 'set_completed_at callback' do
      it 'sets completed_at when marking as completed' do
        item = create(:list_item, completed: false)

        travel_to Time.current do
          item.update!(completed: true)
          expect(item.completed_at).to be_within(1.second).of(Time.current)
        end
      end

      it 'clears completed_at when marking as pending' do
        item = create(:list_item, :completed)

        item.update!(completed: false)
        expect(item.completed_at).to be_nil
      end

      it 'does not change completed_at if completion status unchanged' do
        item = create(:list_item, :completed)
        original_time = item.completed_at

        item.update!(title: 'Updated title')
        expect(item.completed_at).to eq(original_time)
      end
    end
  end

  describe '#overdue?' do
    context 'when due_date is not set' do
      it 'returns false' do
        item = create(:list_item, due_date: nil)
        expect(item.overdue?).to be false
      end
    end

    context 'when due_date is in the future' do
      it 'returns false' do
        item = create(:list_item, due_date: 1.hour.from_now)
        expect(item.overdue?).to be false
      end
    end

    context 'when due_date is in the past and item is not completed' do
      it 'returns true' do
        item = create(:list_item, :overdue, completed: false)
        expect(item.overdue?).to be true
      end
    end

    context 'when due_date is in the past but item is completed' do
      it 'returns false' do
        item = create(:list_item, :overdue, :completed)
        expect(item.overdue?).to be false
      end
    end

    context 'when due_date is exactly now' do
      it 'returns false' do
        travel_to Time.current do
          item = create(:list_item, due_date: Time.current, completed: false)
          expect(item.overdue?).to be false
        end
      end
    end
  end

  describe '#editable_by?' do
    let(:owner) { create(:user, :verified) }
    let(:collaborator) { create(:user, :verified) }
    let(:assigned_user) { create(:user, :verified) }
    let(:other_user) { create(:user, :verified) }
    let(:list) { create(:list, owner: owner) }
    let(:item) { create(:list_item, list: list, assigned_user: assigned_user) }

    before do
      create(:list_collaboration, :collaborate_permission, list: list, user: collaborator)
    end

    it 'returns true for list owner' do
      expect(item.editable_by?(owner)).to be true
    end

    it 'returns true for collaborator with edit permission' do
      expect(item.editable_by?(collaborator)).to be true
    end

    it 'returns true for assigned user' do
      expect(item.editable_by?(assigned_user)).to be true
    end

    it 'returns false for user without permissions' do
      expect(item.editable_by?(other_user)).to be false
    end

    it 'returns false for nil user' do
      expect(item.editable_by?(nil)).to be false
    end

    context 'with read-only collaborator' do
      let(:read_only_user) { create(:user, :verified) }

      before do
        create(:list_collaboration, :read_permission, list: list, user: read_only_user)
      end

      it 'returns false for read-only collaborator' do
        expect(item.editable_by?(read_only_user)).to be false
      end
    end
  end

  describe 'item types' do
    describe 'task items' do
      it 'creates task items correctly' do
        task = create(:list_item, :task)
        expect(task.item_type_task?).to be true
      end
    end

    describe 'note items' do
      it 'creates note items correctly' do
        note = create(:list_item, :note)
        expect(note.item_type_note?).to be true
      end
    end

    describe 'link items' do
      it 'creates link items with URL' do
        link_item = create(:list_item, :link)
        expect(link_item.item_type_link?).to be true
        expect(link_item.url).to be_present
      end
    end

    describe 'file items' do
      it 'creates file items correctly' do
        file_item = create(:list_item, :file)
        expect(file_item.item_type_file?).to be true
      end
    end

    describe 'reminder items' do
      it 'creates reminder items with reminder_at' do
        reminder = create(:list_item, :reminder)
        expect(reminder.item_type_reminder?).to be true
        expect(reminder.reminder_at).to be_present
      end
    end
  end

  describe 'priority levels' do
    it 'handles all priority levels correctly' do
      low = create(:list_item, :low_priority)
      medium = create(:list_item, :medium_priority)
      high = create(:list_item, :high_priority)
      urgent = create(:list_item, :urgent_priority)

      expect(low.priority_low?).to be true
      expect(medium.priority_medium?).to be true
      expect(high.priority_high?).to be true
      expect(urgent.priority_urgent?).to be true
    end
  end

  describe 'due date handling' do
    describe 'due today' do
      it 'creates items due today' do
        item = create(:list_item, :due_today)
        expect(item.due_date.to_date).to eq(Date.current)
      end
    end

    describe 'due tomorrow' do
      it 'creates items due tomorrow' do
        item = create(:list_item, :due_tomorrow)
        expect(item.due_date.to_date).to eq(Date.current + 1.day)
      end
    end

    describe 'overdue items' do
      it 'creates overdue items' do
        item = create(:list_item, :overdue)
        expect(item.due_date).to be < Time.current
        expect(item.overdue?).to be true
      end
    end
  end

  describe 'assignment functionality' do
    it 'can be assigned to a user' do
      user = create(:user, :verified)
      item = create(:list_item, :with_assignment, assigned_user: user)

      expect(item.assigned_user).to eq(user)
    end

    it 'can exist without assignment' do
      item = create(:list_item, assigned_user: nil)
      expect(item.assigned_user).to be_nil
    end
  end

  describe 'position handling' do
    it 'defaults to position 0' do
      item = create(:list_item)
      expect(item.position).to eq(0)
    end

    it 'can be set to custom position' do
      item = create(:list_item, position: 5)
      expect(item.position).to eq(5)
    end
  end

  describe 'metadata handling' do
    it 'accepts JSON metadata' do
      metadata = { 'tags' => [ 'important' ], 'color' => 'red' }
      item = create(:list_item, metadata: metadata)

      expect(item.metadata).to eq(metadata)
    end

    it 'handles nil metadata' do
      item = create(:list_item, metadata: nil)
      expect(item.metadata).to be_nil
    end
  end

  describe 'UUID primary key' do
    it 'uses UUID as primary key' do
      expect(list_item.id).to be_present
      expect(list_item.id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it 'generates unique UUIDs' do
      item1 = create(:list_item)
      item2 = create(:list_item)

      expect(item1.id).not_to eq(item2.id)
    end
  end

  describe 'list association' do
    it 'belongs to a list' do
      expect(list_item.list).to be_present
      expect(list_item.list).to be_a(List)
    end

    it 'is destroyed when list is destroyed' do
      list = create(:list)
      item = create(:list_item, list: list)

      expect { list.destroy }.to change { ListItem.count }.by(-1)
    end
  end

  describe 'factories and traits' do
    it 'creates valid items with all factory traits' do
      traits = [
        [ :task ], [ :note ], [ :link ], [ :file ], [ :reminder ],
        [ :low_priority ], [ :medium_priority ], [ :high_priority ], [ :urgent_priority ],
        [ :completed ], [ :pending ],
        [ :due_today ], [ :due_tomorrow ], [ :overdue ],
        [ :with_assignment ]
      ]

      traits.each do |trait|
        expect(build(:list_item, *trait)).to be_valid
      end
    end
  end

  describe 'validation edge cases' do
    it 'handles whitespace-only titles correctly' do
      item = build(:list_item, title: '   ')
      expect(item).not_to be_valid
      expect(item.errors[:title]).to be_present
    end

    it 'handles Unicode characters in title' do
      unicode_title = '📝 Unicode Task ✅'
      item = create(:list_item, title: unicode_title)
      expect(item.title).to eq(unicode_title)
    end

    it 'handles special characters in description' do
      special_desc = "Task with special chars: @#$%^&*(){}[]|\\:;\"'<>?,./"
      item = create(:list_item, description: special_desc)
      expect(item.description).to eq(special_desc)
    end
  end
end
