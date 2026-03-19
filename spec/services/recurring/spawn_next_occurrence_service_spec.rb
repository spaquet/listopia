require 'rails_helper'

RSpec.describe Recurring::SpawnNextOccurrenceService, type: :service do
  let(:user) { create(:user) }
  let(:list) { create(:list, owner: user) }
  let(:item) do
    create(:list_item,
           list: list,
           recurrence_rule: 'weekly',
           due_date: Time.zone.now + 1.day,
           title: 'Weekly Meeting',
           description: 'Team sync',
           priority: :high,
           assigned_user: user)
  end

  describe '#call' do
    context 'when item is not recurring' do
      it 'returns success with nil data' do
        item.update!(recurrence_rule: 'none')
        service = Recurring::SpawnNextOccurrenceService.new(item)
        result = service.call

        expect(result.success?).to be true
        expect(result.data).to be_nil
      end
    end

    context 'when item is outside recurrence window' do
      it 'returns success with nil data' do
        # Set due date 2 weeks ago, end date before next_due_date
        # Due date: 2 weeks ago = Time.zone.now - 14.days
        # Recurrence: weekly
        # Next due date: (Time.zone.now - 14.days) + 7.days = Time.zone.now - 7.days
        # End date: 10 days ago
        # Is next_due_date (-7 days) <= end_date (-10 days)? NO, so it's outside window
        item.update!(
          due_date: Time.zone.now - 14.days,
          recurrence_rule: 'weekly',
          recurrence_end_date: Time.zone.now - 10.days
        )
        service = Recurring::SpawnNextOccurrenceService.new(item)
        result = service.call

        expect(result.success?).to be true
        expect(result.data).to be_nil
      end
    end

    context 'when item is recurring and within window' do
      it 'creates a new item with copied attributes' do
        service = Recurring::SpawnNextOccurrenceService.new(item)
        expect {
          service.call
        }.to change(ListItem, :count).by(1)
      end

      it 'sets the new due_date to next_due_date' do
        service = Recurring::SpawnNextOccurrenceService.new(item)
        result = service.call

        expect(result.success?).to be true
        new_item = result.data
        expect(new_item.due_date).to eq(item.next_due_date)
      end

      it 'copies title and description' do
        service = Recurring::SpawnNextOccurrenceService.new(item)
        result = service.call

        new_item = result.data
        expect(new_item.title).to eq(item.title)
        expect(new_item.description).to eq(item.description)
      end

      it 'copies priority and item_type' do
        service = Recurring::SpawnNextOccurrenceService.new(item)
        result = service.call

        new_item = result.data
        expect(new_item.priority).to eq(item.priority)
        expect(new_item.item_type).to eq(item.item_type)
      end

      it 'copies recurrence rule and end date' do
        service = Recurring::SpawnNextOccurrenceService.new(item)
        result = service.call

        new_item = result.data
        expect(new_item.recurrence_rule).to eq(item.recurrence_rule)
        expect(new_item.recurrence_end_date).to eq(item.recurrence_end_date)
      end

      it 'sets new item status to pending' do
        service = Recurring::SpawnNextOccurrenceService.new(item)
        result = service.call

        new_item = result.data
        expect(new_item.status).to eq('pending')
      end
    end

    context 'with daily recurrence' do
      it 'spawns item with correct due date' do
        item.update!(recurrence_rule: 'daily')
        service = Recurring::SpawnNextOccurrenceService.new(item)
        result = service.call

        new_item = result.data
        expect(new_item.due_date).to eq(item.due_date + 1.day)
      end
    end

    context 'with monthly recurrence' do
      it 'spawns item with correct due date' do
        item.update!(recurrence_rule: 'monthly')
        service = Recurring::SpawnNextOccurrenceService.new(item)
        result = service.call

        new_item = result.data
        expect(new_item.due_date).to eq(item.due_date + 1.month)
      end
    end
  end
end
