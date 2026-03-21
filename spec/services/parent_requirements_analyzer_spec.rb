# spec/services/parent_requirements_analyzer_spec.rb

require 'rails_helper'

RSpec.describe ParentRequirementsAnalyzer, type: :service do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, created_by: user) }
  let(:chat) { create(:chat, user: user, organization: organization) }

  describe '#call' do
    context 'with event planning domain' do
      let(:planning_context) do
        create(:planning_context,
          user: user,
          chat: chat,
          organization: organization,
          planning_domain: 'event',
          parameters: { locations: [ 'NYC', 'LA' ], budget: '$50k' }
        )
      end

      it 'generates event-specific parent items' do
        result = described_class.new(planning_context).call

        expect(result).to be_success
        parent_items = result.data[:parent_items]
        titles = parent_items.map { |item| item[:title] }

        expect(titles).to include('Pre-Event Planning')
        expect(titles).to include('Logistics & Operations')
        expect(titles).to include('Marketing & Promotion')
        expect(titles).to include('Post-Event Follow-up')
      end

      it 'updates planning context with parent requirements' do
        result = described_class.new(planning_context).call
        updated_context = result.data[:planning_context]

        expect(updated_context.parent_requirements).to be_present
        expect(updated_context.parent_requirements['items']).to be_an(Array)
        expect(updated_context.parent_requirements['items'].length).to be > 0
      end
    end

    context 'with project planning domain' do
      let(:planning_context) do
        create(:planning_context,
          user: user,
          chat: chat,
          organization: organization,
          planning_domain: 'project',
          parameters: {}
        )
      end

      it 'generates project-specific parent items' do
        result = described_class.new(planning_context).call
        parent_items = result.data[:parent_items]
        titles = parent_items.map { |item| item[:title] }

        expect(titles).to include('Project Initialization')
        expect(titles).to include('Resource & Team Setup')
        expect(titles).to include('Development & Execution')
        expect(titles).to include('Review & Closure')
      end
    end

    context 'with travel planning domain' do
      let(:planning_context) do
        create(:planning_context,
          user: user,
          chat: chat,
          organization: organization,
          planning_domain: 'vacation',
          parameters: {}
        )
      end

      it 'generates travel-specific parent items' do
        result = described_class.new(planning_context).call
        parent_items = result.data[:parent_items]
        titles = parent_items.map { |item| item[:title] }

        expect(titles).to include('Trip Planning')
        expect(titles).to include('Accommodations & Transport')
        expect(titles).to include('Itinerary & Activities')
        expect(titles).to include('Pre-Departure Checklist')
      end
    end

    context 'with generic domain' do
      let(:planning_context) do
        create(:planning_context,
          user: user,
          chat: chat,
          organization: organization,
          planning_domain: 'unknown',
          parameters: {}
        )
      end

      it 'generates generic parent items' do
        result = described_class.new(planning_context).call
        parent_items = result.data[:parent_items]
        titles = parent_items.map { |item| item[:title] }

        expect(titles).to include('Planning')
        expect(titles).to include('Execution')
        expect(titles).to include('Review & Closure')
      end
    end
  end
end
