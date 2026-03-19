require 'rails_helper'

RSpec.describe RecurringItemJob, type: :job do
  let(:user) { create(:user) }
  let(:list) { create(:list, owner: user) }

  describe '#perform' do
    context 'with completed recurring items' do
      let!(:completed_recurring_item) do
        create(:list_item,
               list: list,
               status: :completed,
               completed_at: Time.current,
               recurrence_rule: 'weekly',
               due_date: Time.zone.now - 1.day)
      end

      it 'spawns next occurrence for completed recurring items' do
        expect {
          RecurringItemJob.perform_now
        }.to change(ListItem, :count).by(1)
      end

      it 'creates item with correct due_date' do
        initial_count = list.list_items.count
        RecurringItemJob.perform_now

        expect(list.list_items.count).to eq(initial_count + 1)
        new_item = list.list_items.where.not(id: completed_recurring_item.id).order(:created_at).last
        expect(new_item.due_date).to eq(completed_recurring_item.next_due_date)
      end
    end

    context 'with pending recurring items' do
      let!(:pending_recurring_item) do
        create(:list_item,
               list: list,
               status: :pending,
               recurrence_rule: 'weekly',
               due_date: Time.zone.now)
      end

      it 'does not spawn next occurrence' do
        expect {
          RecurringItemJob.perform_now
        }.not_to change(ListItem, :count)
      end
    end

    context 'with non-recurring items' do
      let!(:non_recurring_item) do
        create(:list_item,
               list: list,
               status: :completed,
               completed_at: Time.current,
               recurrence_rule: 'none')
      end

      it 'does not spawn next occurrence' do
        expect {
          RecurringItemJob.perform_now
        }.not_to change(ListItem, :count)
      end
    end

    context 'with completed item past recurrence window' do
      let!(:past_window_item) do
        create(:list_item,
               list: list,
               status: :completed,
               completed_at: Time.current,
               recurrence_rule: 'weekly',
               due_date: Time.zone.now - 1.week,
               recurrence_end_date: Time.zone.now - 1.day)
      end

      it 'does not spawn next occurrence' do
        expect {
          RecurringItemJob.perform_now
        }.not_to change(ListItem, :count)
      end
    end

    context 'with multiple recurring items' do
      let!(:item1) do
        create(:list_item,
               list: list,
               status: :completed,
               completed_at: Time.current,
               recurrence_rule: 'daily',
               due_date: Time.zone.now - 1.day)
      end

      let!(:item2) do
        create(:list_item,
               list: list,
               status: :completed,
               completed_at: Time.current,
               recurrence_rule: 'weekly',
               due_date: Time.zone.now - 2.days)
      end

      it 'spawns next occurrence for all completed recurring items' do
        expect {
          RecurringItemJob.perform_now
        }.to change(ListItem, :count).by(2)
      end
    end
  end
end
