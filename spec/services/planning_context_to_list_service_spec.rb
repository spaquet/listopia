# spec/services/planning_context_to_list_service_spec.rb

require 'rails_helper'

RSpec.describe PlanningContextToListService, type: :service do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, created_by: user) }
  let(:chat) { create(:chat, user: user, organization: organization) }

  describe '#call' do
    context 'with completed planning context' do
      let(:planning_context) do
        create(:planning_context,
          user: user,
          chat: chat,
          organization: organization,
          request_content: 'Plan US roadshow',
          state: 'completed',
          parent_requirements: {
            'items' => [
              { title: 'Planning', description: 'Planning phase', priority: 'high' },
              { title: 'Execution', description: 'Execution phase', priority: 'high' }
            ]
          },
          hierarchical_items: {
            'parent_items' => [],
            'subdivisions' => {
              'New York' => {
                title: 'New York',
                items: [
                  { title: 'Venue booking', description: 'Book venue', priority: 'high' },
                  { title: 'Logistics', description: 'Arrange transport', priority: 'medium' }
                ]
              },
              'Los Angeles' => {
                title: 'Los Angeles',
                items: [
                  { title: 'Venue booking', description: 'Book venue', priority: 'high' }
                ]
              }
            },
            'subdivision_type' => 'locations'
          }
        )
      end

      it 'creates a list with parent items' do
        result = described_class.new(planning_context, user, organization).call

        expect(result).to be_success
        list = result.data[:list]
        expect(list.title).to be_present
        expect(list.list_items.count).to be > 0
      end

      it 'creates sublists for each subdivision' do
        result = described_class.new(planning_context, user, organization).call

        list = result.data[:list]
        expect(list.sub_lists.count).to eq(2)
        sublist_titles = list.sub_lists.pluck(:title)
        expect(sublist_titles).to include('New York', 'Los Angeles')
      end

      it 'creates items in sublists' do
        result = described_class.new(planning_context, user, organization).call

        list = result.data[:list]
        ny_sublist = list.sub_lists.find_by(title: 'New York')
        expect(ny_sublist.list_items.count).to eq(2)
      end

      it 'updates planning context with list_created_id' do
        result = described_class.new(planning_context, user, organization).call

        updated_context = result.data[:planning_context]
        expect(updated_context.list_created_id).to be_present
        expect(updated_context.list_created_id).to eq(result.data[:list].id)
      end

      it 'sets planning context state to resource_creation' do
        result = described_class.new(planning_context, user, organization).call

        updated_context = result.data[:planning_context]
        expect(updated_context.state).to eq('resource_creation')
      end
    end

    context 'with non-completed planning context' do
      let(:planning_context) do
        create(:planning_context,
          user: user,
          chat: chat,
          organization: organization,
          state: 'pre_creation'
        )
      end

      it 'returns failure' do
        result = described_class.new(planning_context, user, organization).call

        expect(result).to be_failure
        expect(result.errors).to include(match(/completed state/))
      end
    end

    context 'with no hierarchical items' do
      let(:planning_context) do
        create(:planning_context,
          user: user,
          chat: chat,
          organization: organization,
          state: 'completed',
          hierarchical_items: {}
        )
      end

      it 'returns failure' do
        result = described_class.new(planning_context, user, organization).call

        expect(result).to be_failure
        expect(result.errors).to include(match(/hierarchical items/))
      end
    end

    context 'with simple list (no subdivisions)' do
      let(:planning_context) do
        create(:planning_context,
          user: user,
          chat: chat,
          organization: organization,
          state: 'completed',
          request_content: 'Grocery list',
          parent_requirements: {
            'items' => [
              { title: 'Produce', description: '', priority: 'medium' },
              { title: 'Dairy', description: '', priority: 'medium' }
            ]
          },
          hierarchical_items: {
            'parent_items' => [],
            'subdivisions' => {},
            'subdivision_type' => 'none'
          }
        )
      end

      it 'creates a simple list with parent items only' do
        result = described_class.new(planning_context, user, organization).call

        expect(result).to be_success
        list = result.data[:list]
        expect(list.list_items.count).to eq(2)
        expect(list.sub_lists.count).to eq(0)
      end
    end
  end
end
