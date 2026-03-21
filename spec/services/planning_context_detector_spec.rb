# spec/services/planning_context_detector_spec.rb

require 'rails_helper'

RSpec.describe PlanningContextDetector, type: :service do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, created_by: user) }
  let(:chat) { create(:chat, user: user, organization: organization) }
  let(:user_message) { create(:message, :user_message, chat: chat, user: user) }

  describe '#call' do
    context 'with list creation intent' do
      before do
        user_message.update(content: 'Help me plan a roadshow')
        allow_any_instance_of(CombinedIntentComplexityService).to receive(:call).and_return(
          ApplicationService::Result.success(data: {
            intent: 'create_list',
            confidence: 0.95,
            planning_domain: 'event',
            is_complex: true,
            complexity_reasoning: 'Multi-location, time-bound event',
            parameters: { title: 'Roadshow', category: 'professional' }
          })
        )
      end

      it 'creates a planning context' do
        expect {
          described_class.new(user_message, chat, user, organization).call
        }.to change(PlanningContext, :count).by(1)
      end

      it 'sets correct attributes on planning context' do
        service = described_class.new(user_message, chat, user, organization)
        result = service.call

        expect(result).to be_success
        planning_context = result.data[:planning_context]
        expect(planning_context.user).to eq(user)
        expect(planning_context.chat).to eq(chat)
        expect(planning_context.organization).to eq(organization)
        expect(planning_context.detected_intent).to eq('create_list')
        expect(planning_context.planning_domain).to eq('event')
        expect(planning_context.is_complex).to be true
        expect(planning_context.state).to eq('initial')
      end

      it 'returns should_create_context: true' do
        result = described_class.new(user_message, chat, user, organization).call

        expect(result.data[:should_create_context]).to be true
      end
    end

    context 'with non-list creation intent' do
      before do
        user_message.update(content: 'What is the weather today?')
        allow_any_instance_of(CombinedIntentComplexityService).to receive(:call).and_return(
          ApplicationService::Result.success(data: {
            intent: 'general_question',
            confidence: 0.90
          })
        )
      end

      it 'does not create a planning context' do
        expect {
          described_class.new(user_message, chat, user, organization).call
        }.not_to change(PlanningContext, :count)
      end

      it 'returns should_create_context: false' do
        result = described_class.new(user_message, chat, user, organization).call

        expect(result.data[:should_create_context]).to be false
      end
    end

    context 'when intent detection fails' do
      before do
        allow_any_instance_of(CombinedIntentComplexityService).to receive(:call).and_return(
          ApplicationService::Result.failure(errors: [ 'Intent detection failed' ])
        )
      end

      it 'returns failure' do
        result = described_class.new(user_message, chat, user, organization).call

        expect(result).to be_failure
        expect(result.errors).to include('Intent detection failed')
      end
    end
  end
end
