require 'rails_helper'

RSpec.describe ListItem, type: :model do
  let(:user) { create(:user) }
  let(:list) { create(:list, owner: user) }
  let(:item) { create(:list_item, list: list, due_date: Time.zone.now + 1.day) }

  describe 'validations' do
    it { expect(item).to validate_inclusion_of(:recurrence_rule).in_array(Recurrence::RULES) }

    context 'when recurrence_end_date is before due_date' do
      it 'adds an error' do
        item.recurrence_rule = 'weekly'
        item.recurrence_end_date = item.due_date - 1.day
        expect(item).not_to be_valid
        expect(item.errors[:recurrence_end_date]).to be_present
      end
    end

    context 'when recurrence_end_date is after due_date' do
      it 'is valid' do
        item.recurrence_rule = 'weekly'
        item.recurrence_end_date = item.due_date + 1.week
        expect(item).to be_valid
      end
    end

    context 'when recurrence_end_date is blank' do
      it 'is valid' do
        item.recurrence_rule = 'weekly'
        item.recurrence_end_date = nil
        expect(item).to be_valid
      end
    end
  end

  describe '#recurring?' do
    it 'returns true when recurrence_rule is not none' do
      item.update!(recurrence_rule: 'weekly')
      expect(item.recurring?).to be true
    end

    it 'returns false when recurrence_rule is none' do
      item.update!(recurrence_rule: 'none')
      expect(item.recurring?).to be false
    end
  end

  describe '#next_due_date' do
    it 'returns nil when item is not recurring' do
      item.update!(recurrence_rule: 'none')
      expect(item.next_due_date).to be_nil
    end

    it 'returns nil when due_date is blank' do
      item.update!(recurrence_rule: 'daily', due_date: nil)
      expect(item.next_due_date).to be_nil
    end

    it 'returns due_date + 1 day for daily recurrence' do
      item.update!(recurrence_rule: 'daily')
      expect(item.next_due_date).to eq(item.due_date + 1.day)
    end

    it 'returns due_date + 1 week for weekly recurrence' do
      item.update!(recurrence_rule: 'weekly')
      expect(item.next_due_date).to eq(item.due_date + 1.week)
    end

    it 'returns due_date + 2 weeks for biweekly recurrence' do
      item.update!(recurrence_rule: 'biweekly')
      expect(item.next_due_date).to eq(item.due_date + 2.weeks)
    end

    it 'returns due_date + 1 month for monthly recurrence' do
      item.update!(recurrence_rule: 'monthly')
      expect(item.next_due_date).to eq(item.due_date + 1.month)
    end

    it 'returns due_date + 1 year for yearly recurrence' do
      item.update!(recurrence_rule: 'yearly')
      expect(item.next_due_date).to eq(item.due_date + 1.year)
    end
  end

  describe '#within_recurrence_window?' do
    context 'when recurrence_end_date is blank' do
      it 'returns true' do
        item.update!(recurrence_rule: 'weekly', recurrence_end_date: nil)
        expect(item.within_recurrence_window?).to be true
      end
    end

    context 'when next_due_date is before recurrence_end_date' do
      it 'returns true' do
        item.update!(
          recurrence_rule: 'weekly',
          recurrence_end_date: item.due_date + 3.weeks
        )
        expect(item.within_recurrence_window?).to be true
      end
    end

    context 'when next_due_date is after recurrence_end_date' do
      it 'returns false' do
        item.update!(
          recurrence_rule: 'weekly',
          recurrence_end_date: item.due_date + 3.days
        )
        expect(item.within_recurrence_window?).to be false
      end
    end

    context 'when next_due_date equals recurrence_end_date' do
      it 'returns true' do
        item.update!(
          recurrence_rule: 'weekly',
          recurrence_end_date: item.due_date + 1.week
        )
        expect(item.within_recurrence_window?).to be true
      end
    end
  end

  describe 'scope :recurring' do
    before do
      create(:list_item, list: list, recurrence_rule: 'weekly')
      create(:list_item, list: list, recurrence_rule: 'none')
      create(:list_item, list: list, recurrence_rule: 'daily')
    end

    it 'returns only recurring items' do
      recurring_items = ListItem.recurring
      expect(recurring_items.count).to eq(2)
      expect(recurring_items.pluck(:recurrence_rule)).not_to include('none')
    end
  end
end
