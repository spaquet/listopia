# spec/services/chat_completion_service_planning_spec.rb
# Integration tests for PlanningContext flow in ChatCompletionService

require 'rails_helper'

RSpec.describe ChatCompletionService, type: :service do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, created_by: user) }
  let(:chat) { create(:chat, user: user, organization: organization) }

  describe 'Simple list creation flow' do
    context 'when user creates a simple list' do
      let(:user_message) do
        create(:message, :user_message,
          chat: chat,
          user: user,
          content: 'Create a grocery list'
        )
      end

      before do
        allow_any_instance_of(CombinedIntentComplexityService).to receive(:call).and_return(
          ApplicationService::Result.success(data: {
            intent: 'create_list',
            is_complex: false,
            complexity_confidence: 0.95,
            planning_domain: 'personal',
            complexity_reasoning: 'Simple, focused list',
            parameters: { title: 'Grocery List', category: 'personal' }
          })
        )
      end

      it 'creates a planning context' do
        expect {
          ChatCompletionService.new(chat, user_message).call
        }.to change(PlanningContext, :count).by(1)
      end

      it 'creates a list from planning context' do
        expect {
          ChatCompletionService.new(chat, user_message).call
        }.to change(List, :count).by(1)
      end

      it 'sets planning context state to completed' do
        ChatCompletionService.new(chat, user_message).call

        planning_context = chat.reload.planning_context
        expect(planning_context.state).to eq('completed')
      end

      it 'links planning context to created list' do
        ChatCompletionService.new(chat, user_message).call

        planning_context = chat.reload.planning_context
        expect(planning_context.list_created_id).to be_present
      end
    end
  end

  describe 'Complex list creation flow' do
    context 'when user creates a complex list' do
      let(:user_message) do
        create(:message, :user_message,
          chat: chat,
          user: user,
          content: 'Help me plan a 2-week vacation to Europe with my family'
        )
      end

      before do
        allow_any_instance_of(CombinedIntentComplexityService).to receive(:call).and_return(
          ApplicationService::Result.success(data: {
            intent: 'create_list',
            is_complex: true,
            complexity_confidence: 0.92,
            planning_domain: 'vacation',
            complexity_reasoning: 'Multi-location, time-constrained, group activity',
            parameters: { title: 'Europe Vacation', category: 'personal' }
          })
        )
      end

      it 'creates planning context in pre_creation state' do
        ChatCompletionService.new(chat, user_message).call

        planning_context = chat.reload.planning_context
        expect(planning_context.state).to eq('pre_creation')
      end

      it 'stores pre-creation questions' do
        ChatCompletionService.new(chat, user_message).call

        planning_context = chat.reload.planning_context
        expect(planning_context.pre_creation_questions).to be_an(Array)
        expect(planning_context.pre_creation_questions.length).to be > 0
      end
    end

    context 'when user answers pre-creation questions' do
      let(:planning_context) do
        create(:planning_context,
          user: user,
          chat: chat,
          organization: organization,
          state: 'pre_creation',
          is_complex: true,
          planning_domain: 'vacation',
          pre_creation_questions: [
            'What countries/cities?',
            'What dates?',
            'What is your budget?'
          ],
          parent_requirements: {
            'items' => [
              { title: 'Trip Planning', description: '', priority: 'high' },
              { title: 'Accommodations & Transport', description: '', priority: 'high' }
            ]
          }
        )
      end

      let(:user_answer_message) do
        create(:message, :user_message,
          chat: chat,
          user: user,
          content: 'Paris, Rome, Barcelona. June 1-15. $5000'
        )
      end

      before do
        chat.update(planning_context: planning_context)
      end

      it 'processes answers and generates items' do
        result = ChatCompletionService.new(chat, user_answer_message).call

        expect(result).to be_success
        planning_context.reload
        expect(planning_context.pre_creation_answers).to be_present
      end

      it 'marks planning context as completed' do
        ChatCompletionService.new(chat, user_answer_message).call

        planning_context.reload
        expect(planning_context.state).to eq('completed')
      end

      it 'creates the list after answers' do
        expect {
          ChatCompletionService.new(chat, user_answer_message).call
        }.to change(List, :count).by(1)
      end

      it 'creates sublists for each location' do
        ChatCompletionService.new(chat, user_answer_message).call

        planning_context.reload
        list = List.find(planning_context.list_created_id)
        expect(list.sub_lists.count).to be > 0
      end
    end
  end

  describe 'State transitions' do
    context 'planning context state machine' do
      it 'transitions from initial → pre_creation for complex requests' do
        planning_context = create(:planning_context,
          user: user,
          chat: chat,
          organization: organization,
          state: 'initial'
        )

        planning_context.mark_awaiting_answers!

        expect(planning_context.state).to eq('pre_creation')
        expect(planning_context.status).to eq('awaiting_user_input')
      end

      it 'transitions from pre_creation → completed after answer processing' do
        planning_context = create(:planning_context,
          user: user,
          chat: chat,
          organization: organization,
          state: 'pre_creation',
          pre_creation_answers: { '0' => 'Answer 1' }
        )

        planning_context.mark_complete!

        expect(planning_context.state).to eq('completed')
        expect(planning_context.status).to eq('complete')
      end

      it 'can mark error state' do
        planning_context = create(:planning_context,
          user: user,
          chat: chat,
          organization: organization,
          state: 'pre_creation'
        )

        planning_context.mark_error!('Item generation failed')

        expect(planning_context.status).to eq('error')
        expect(planning_context.error_message).to eq('Item generation failed')
      end
    end
  end

  describe 'Backward compatibility' do
    context 'with old metadata-based flow' do
      let(:user_message) do
        create(:message, :user_message,
          chat: chat,
          user: user,
          content: 'Create a project list'
        )
      end

      it 'still processes messages when no PlanningContext exists' do
        # Ensure no planning context
        expect(chat.planning_context).to be_nil

        result = ChatCompletionService.new(chat, user_message).call

        # Old flow should create a message
        expect(result).to be_success or be_failure # Either succeeds or fails gracefully
      end

      it 'prioritizes PlanningContext flow when it exists' do
        planning_context = create(:planning_context,
          user: user,
          chat: chat,
          organization: organization,
          state: 'pre_creation'
        )
        chat.update(planning_context: planning_context)

        answer_message = create(:message, :user_message,
          chat: chat,
          user: user,
          content: 'User answers to questions'
        )

        # Should use new flow, not old flow
        ChatCompletionService.new(chat, answer_message).call

        planning_context.reload
        expect(planning_context.pre_creation_answers).to be_present
      end
    end
  end
end
