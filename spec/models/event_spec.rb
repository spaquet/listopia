# == Schema Information
#
# Table name: events
#
#  id              :uuid             not null, primary key
#  event_data      :jsonb
#  event_type      :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  actor_id        :uuid
#  organization_id :uuid             not null
#
# Indexes
#
#  index_events_on_actor_id                        (actor_id)
#  index_events_on_actor_id_and_created_at         (actor_id,created_at)
#  index_events_on_event_type                      (event_type)
#  index_events_on_organization_id                 (organization_id)
#  index_events_on_organization_id_and_created_at  (organization_id,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (actor_id => users.id)
#  fk_rails_...  (organization_id => organizations.id)
#
require 'rails_helper'

RSpec.describe Event, type: :model do
  let(:user) { create(:user) }
  let(:organization) { create(:organization) }

  before do
    user.organizations << organization
  end

  describe 'associations' do
    it { is_expected.to belong_to(:organization) }
    it { is_expected.to belong_to(:actor).class_name('User').optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:event_type) }
    it { is_expected.to validate_presence_of(:organization_id) }
  end

  describe '.emit' do
    it 'creates an event with the given parameters' do
      event = Event.emit(
        'list_item.created',
        organization.id,
        user.id,
        { item_id: '123', title: 'Test' }
      )

      expect(event).to be_persisted
      expect(event.event_type).to eq('list_item.created')
      expect(event.actor_id).to eq(user.id)
      expect(event.event_data).to eq({ 'item_id' => '123', 'title' => 'Test' })
    end

    it 'allows creating events without an actor' do
      event = Event.emit('system.initialized', organization.id)

      expect(event).to be_persisted
      expect(event.actor_id).to be_nil
    end
  end

  describe 'scopes' do
    before do
      Event.emit('list_item.created', organization.id, user.id)
      Event.emit('list_item.updated', organization.id, user.id)
      Event.emit('list_item.created', organization.id)
    end

    describe '.by_type' do
      it 'returns events of the specified type' do
        events = Event.by_type('list_item.created')
        expect(events.count).to eq(2)
        expect(events.map(&:event_type).uniq).to eq([ 'list_item.created' ])
      end
    end

    describe '.by_actor' do
      it 'returns events created by a specific user' do
        events = Event.by_actor(user)
        expect(events.count).to eq(2)
        expect(events.map(&:actor_id).uniq).to eq([ user.id ])
      end
    end

    describe '.recent' do
      it 'returns events in reverse chronological order' do
        events = Event.recent.limit(2)
        expect(events.first.created_at).to be >= events.last.created_at
      end
    end

    describe '.since' do
      it 'returns events since a given timestamp' do
        time = 1.minute.ago
        Event.emit('list_item.created', organization.id, user.id)
        events = Event.since(time)
        expect(events.count).to be >= 1
      end
    end
  end
end
