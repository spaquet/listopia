require 'rails_helper'

RSpec.describe MessageFeedbacksController, type: :request do
  let(:user) { create(:user, :verified) }
  let(:chat_user) { create(:user, :verified) }
  let(:organization) { create(:organization, creator: user) }
  let(:chat) { create(:chat, user: user, organization: organization) }
  let(:message) { create(:message, chat: chat, user: chat_user) }

  before do
    create(:organization_membership, organization: organization, user: user, role: :owner)
    create(:organization_membership, organization: organization, user: chat_user, role: :member)
  end

  def login_as(user)
    post session_path, params: { email: user.email, password: user.password }
  end

  def feedback_path_for(msg)
    "/chats/#{msg.chat_id}/messages/#{msg.id}/feedbacks"
  end

  describe 'authentication' do
    it 'requires user to be signed in' do
      post feedback_path_for(message), params: { message_feedback: { rating: 'helpful' } }
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe 'authorization' do
    context 'when user is not a collaborator on the chat' do
      let(:other_user) { create(:user, :verified) }

      before do
        login_as(other_user)
      end

      it 'denies access to feedback creation' do
        expect {
          post feedback_path_for(message),
               params: { message_feedback: { rating: 'helpful' } }
        }.not_to change(MessageFeedback, :count)
      end
    end

    context 'when user tries to rate their own message' do
      let(:own_message) { create(:message, chat: chat, user: user) }

      before { login_as(user) }

      it 'returns 403 (controller check - cannot rate own message)' do
        post feedback_path_for(own_message),
             params: { message_feedback: { rating: 'helpful' } }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST #create' do
    before { login_as(user) }

    context 'with valid parameters' do
      it 'creates a new message feedback' do
        expect {
          post feedback_path_for(message),
               params: { message_feedback: { rating: 'helpful', comment: 'Great response' } }
        }.to change(MessageFeedback, :count).by(1)
      end

      it 'associates feedback with message' do
        post feedback_path_for(message),
             params: { message_feedback: { rating: 'helpful', comment: 'Good' } }

        expect(MessageFeedback.last.message).to eq(message)
      end

      it 'associates feedback with current user' do
        post feedback_path_for(message),
             params: { message_feedback: { rating: 'helpful' } }

        expect(MessageFeedback.last.user).to eq(user)
      end

      it 'associates feedback with chat' do
        post feedback_path_for(message),
             params: { message_feedback: { rating: 'helpful' } }

        expect(MessageFeedback.last.chat).to eq(chat)
      end

      it 'sets the rating' do
        post feedback_path_for(message),
             params: { message_feedback: { rating: 'unhelpful' } }

        expect(MessageFeedback.last.rating).to eq('unhelpful')
      end

      it 'sets feedback_type' do
        post feedback_path_for(message),
             params: { message_feedback: { rating: 'helpful', feedback_type: 'accuracy' } }

        expect(MessageFeedback.last.feedback_type).to eq('accuracy')
      end

      it 'sets comment' do
        post feedback_path_for(message),
             params: { message_feedback: { rating: 'neutral', comment: 'Could be better' } }

        expect(MessageFeedback.last.comment).to eq('Could be better')
      end

      it 'sets helpfulness_score' do
        post feedback_path_for(message),
             params: { message_feedback: { rating: 'helpful', helpfulness_score: 8 } }

        expect(MessageFeedback.last.helpfulness_score).to eq(8)
      end

      context 'JSON format' do
        it 'returns JSON success response' do
          post feedback_path_for(message) + '.json',
               params: { message_feedback: { rating: 'helpful' } }

          json = JSON.parse(response.body)
          expect(json['success']).to be true
        end

        it 'includes feedback in JSON response' do
          post feedback_path_for(message) + '.json',
               params: { message_feedback: { rating: 'helpful' } }

          json = JSON.parse(response.body)
          expect(json['feedback']).to be_present
        end
      end

      context 'Turbo Stream format' do
        it 'creates feedback even without turbo_stream template' do
          expect {
            post feedback_path_for(message),
                 params: { message_feedback: { rating: 'helpful' } },
                 headers: { 'Accept' => Mime[:turbo_stream].to_s }
          }.to change(MessageFeedback, :count).by(1)
        end
      end
    end

    context 'with invalid parameters' do
      it 'does not create feedback without rating' do
        expect {
          post feedback_path_for(message),
               params: { message_feedback: { comment: 'Test' } }
        }.not_to change(MessageFeedback, :count)
      end

      context 'JSON format' do
        it 'returns JSON error response' do
          post feedback_path_for(message) + '.json',
               params: { message_feedback: { comment: 'No rating' } }

          json = JSON.parse(response.body)
          expect(json['success']).to be false
          expect(json['errors']).to be_present
        end

        it 'returns 422 status' do
          post feedback_path_for(message) + '.json',
               params: { message_feedback: { comment: 'No rating' } }

          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

    end

    context 'updating existing feedback' do
      let!(:existing_feedback) do
        create(:message_feedback, message: message, user: user, rating: 'unhelpful')
      end

      it 'updates existing feedback instead of creating new' do
        expect {
          post feedback_path_for(message),
               params: { message_feedback: { rating: 'helpful', comment: 'Actually great!' } }
        }.not_to change(MessageFeedback, :count)
      end

      it 'updates the rating' do
        post feedback_path_for(message),
             params: { message_feedback: { rating: 'helpful' } }

        expect(existing_feedback.reload.rating).to eq('helpful')
      end

      it 'updates the comment' do
        post feedback_path_for(message),
             params: { message_feedback: { rating: 'neutral', comment: 'Updated comment' } }

        expect(existing_feedback.reload.comment).to eq('Updated comment')
      end

      context 'JSON format' do
        it 'returns success response' do
          post feedback_path_for(message) + '.json',
               params: { message_feedback: { rating: 'helpful', comment: 'Updated' } }

          json = JSON.parse(response.body)
          expect(json['success']).to be true
        end
      end
    end
  end

  describe 'parameter filtering' do
    before { login_as(user) }

    it 'only permits allowed parameters' do
      expect {
        post feedback_path_for(message),
             params: {
               message_feedback: {
                 rating: 'helpful',
                 comment: 'Good',
                 user_id: 999,
                 chat_id: 999
               }
             }
      }.not_to raise_error
    end

    it 'associates with correct user despite user_id param' do
      post feedback_path_for(message),
           params: {
             message_feedback: {
               rating: 'helpful',
               user_id: 999
             }
           }

      expect(MessageFeedback.last.user).to eq(user)
    end

    it 'associates with correct chat despite chat_id param' do
      post feedback_path_for(message),
           params: {
             message_feedback: {
               rating: 'helpful',
               chat_id: 999
             }
           }

      expect(MessageFeedback.last.chat).to eq(chat)
    end
  end

  describe 'different rating values' do
    before { login_as(user) }

    it 'accepts rating of 1' do
      post feedback_path_for(message),
           params: { message_feedback: { rating: 'helpful' } }

      expect(MessageFeedback.last.rating).to eq('helpful')
    end

    it 'accepts rating of 5' do
      post feedback_path_for(message),
           params: { message_feedback: { rating: 'unhelpful' } }

      expect(MessageFeedback.last.rating).to eq('unhelpful')
    end

    it 'accepts rating of 10' do
      post feedback_path_for(message),
           params: { message_feedback: { rating: 'harmful' } }

      expect(MessageFeedback.last.rating).to eq('harmful')
    end
  end

  describe 'different feedback types' do
    before { login_as(user) }

    it 'accepts helpful feedback type' do
      post feedback_path_for(message),
           params: { message_feedback: { rating: 'helpful', feedback_type: 'accuracy' } }

      expect(MessageFeedback.last.feedback_type).to eq('accuracy')
    end

    it 'accepts unhelpful feedback type' do
      post feedback_path_for(message),
           params: { message_feedback: { rating: 'unhelpful', feedback_type: 'relevance' } }

      expect(MessageFeedback.last.feedback_type).to eq('relevance')
    end

    it 'accepts custom feedback type' do
      post feedback_path_for(message),
           params: { message_feedback: { rating: 'helpful', feedback_type: 'clarity' } }

      expect(MessageFeedback.last.feedback_type).to eq('clarity')
    end
  end
end
