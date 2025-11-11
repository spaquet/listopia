# spec/requests/comments_controller_spec.rb
require 'rails_helper'

RSpec.describe CommentsController, type: :request do
  let(:user) { create(:user, :verified) }
  let(:other_user) { create(:user, :verified) }
  let(:list_owner) { create(:user, :verified) }
  let(:list) { create(:list, owner: list_owner) }
  let(:list_item) { create(:list_item, list: list) }

  describe 'authentication' do
    it 'requires user to be signed in to create comment' do
      post list_comments_path(list), params: { comment: { content: 'Test' } }
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in to delete comment' do
      comment = create(:comment, user: user, commentable: list)
      delete list_comment_path(list, comment)
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe 'POST #create on List' do
    before { sign_in user }

    context 'with valid parameters' do
      it 'creates a new comment' do
        list.collaborators.create!(user: user, permission: :comment)

        expect {
          post list_comments_path(list), params: { comment: { content: 'Great list!' } }
        }.to change(Comment, :count).by(1)
      end

      it 'associates comment with list' do
        list.collaborators.create!(user: user, permission: :comment)

        post list_comments_path(list), params: { comment: { content: 'Test comment' } }

        comment = Comment.last
        expect(comment.commentable).to eq(list)
        expect(comment.user).to eq(user)
      end

      it 'associates comment with current user' do
        list.collaborators.create!(user: user, permission: :comment)

        post list_comments_path(list), params: { comment: { content: 'Test' } }

        expect(Comment.last.user).to eq(user)
      end

      it 'responds with turbo_stream format' do
        list.collaborators.create!(user: user, permission: :comment)

        post list_comments_path(list),
             params: { comment: { content: 'Test' } },
             headers: { accept: 'text/vnd.turbo-stream.html' }

        expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      end

      it 'renders comments container update in turbo response' do
        list.collaborators.create!(user: user, permission: :comment)

        post list_comments_path(list),
             params: { comment: { content: 'Test' } },
             headers: { accept: 'text/vnd.turbo-stream.html' }

        expect(response.body).to include('comments_container')
      end

      it 'renders form reset in turbo response' do
        list.collaborators.create!(user: user, permission: :comment)

        post list_comments_path(list),
             params: { comment: { content: 'Test' } },
             headers: { accept: 'text/vnd.turbo-stream.html' }

        expect(response.body).to include('new_comment_form')
      end

      it 'responds with HTML redirect' do
        list.collaborators.create!(user: user, permission: :comment)

        post list_comments_path(list), params: { comment: { content: 'Test' } }

        expect(response).to redirect_to(list)
      end
    end

    context 'with invalid parameters' do
      it 'does not create comment with blank content' do
        list.collaborators.create!(user: user, permission: :comment)

        expect {
          post list_comments_path(list), params: { comment: { content: '' } }
        }.not_to change(Comment, :count)
      end

      it 'returns errors in turbo_stream response' do
        list.collaborators.create!(user: user, permission: :comment)

        post list_comments_path(list),
             params: { comment: { content: '' } },
             headers: { accept: 'text/vnd.turbo-stream.html' }

        expect(response.status).to eq(422)
        expect(response.body).to include('new_comment_form')
      end

      it 'returns error page for HTML request' do
        list.collaborators.create!(user: user, permission: :comment)

        post list_comments_path(list), params: { comment: { content: '' } }

        expect(response).to redirect_to(list)
        expect(flash[:alert]).to include('Unable')
      end

      it 'does not create comment exceeding 5000 characters' do
        list.collaborators.create!(user: user, permission: :comment)

        expect {
          post list_comments_path(list),
               params: { comment: { content: 'a' * 5001 } }
        }.not_to change(Comment, :count)
      end
    end

    context 'authorization' do
      it 'denies comment creation without permission' do
        post list_comments_path(list), params: { comment: { content: 'Test' } }

        expect(response).to have_http_status(:forbidden)
      end

      it 'denies user with only view permission' do
        list.collaborators.create!(user: user, permission: :view)

        post list_comments_path(list), params: { comment: { content: 'Test' } }

        expect(response).to have_http_status(:forbidden)
      end

      it 'allows collaborator with comment permission' do
        list.collaborators.create!(user: user, permission: :comment)

        post list_comments_path(list), params: { comment: { content: 'Test' } }

        expect(response).to redirect_to(list)
      end

      it 'allows collaborator with edit permission' do
        list.collaborators.create!(user: user, permission: :edit)

        post list_comments_path(list), params: { comment: { content: 'Test' } }

        expect(response).to redirect_to(list)
      end

      it 'allows list owner to comment' do
        post list_comments_path(list), params: { comment: { content: 'Test' } }

        expect(response).to redirect_to(list)
      end
    end

    context 'with invalid list' do
      it 'returns 404 for non-existent list' do
        post list_comments_path('invalid-id'), params: { comment: { content: 'Test' } }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST #create on ListItem' do
    before { sign_in user }

    context 'with valid parameters' do
      it 'creates a comment on list_item' do
        list.collaborators.create!(user: user, permission: :comment)

        expect {
          post list_list_item_comments_path(list, list_item),
               params: { comment: { content: 'Task comment' } }
        }.to change(Comment, :count).by(1)
      end

      it 'associates comment with list_item' do
        list.collaborators.create!(user: user, permission: :comment)

        post list_list_item_comments_path(list, list_item),
             params: { comment: { content: 'Task comment' } }

        comment = Comment.last
        expect(comment.commentable).to eq(list_item)
      end

      it 'responds with turbo_stream format' do
        list.collaborators.create!(user: user, permission: :comment)

        post list_list_item_comments_path(list, list_item),
             params: { comment: { content: 'Test' } },
             headers: { accept: 'text/vnd.turbo-stream.html' }

        expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      end
    end

    context 'authorization' do
      it 'denies comment creation without permission' do
        post list_list_item_comments_path(list, list_item),
             params: { comment: { content: 'Test' } }

        expect(response).to have_http_status(:forbidden)
      end

      it 'allows collaborator with comment permission' do
        list.collaborators.create!(user: user, permission: :comment)

        post list_list_item_comments_path(list, list_item),
             params: { comment: { content: 'Test' } }

        expect(response).to redirect_to(list)
      end
    end

    context 'with invalid list_item' do
      it 'returns 404 for non-existent list_item' do
        list.collaborators.create!(user: user, permission: :comment)

        post list_list_item_comments_path(list, 'invalid-id'),
             params: { comment: { content: 'Test' } }

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with list_item from different list' do
      let(:other_list) { create(:list, owner: list_owner) }
      let(:other_list_item) { create(:list_item, list: other_list) }

      it 'returns 404 when list_item belongs to different list' do
        list.collaborators.create!(user: user, permission: :comment)

        post list_list_item_comments_path(list, other_list_item),
             params: { comment: { content: 'Test' } }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE #destroy on List' do
    let(:comment) { create(:comment, user: user, commentable: list) }

    before { sign_in user }

    context 'comment author' do
      it 'allows author to delete comment' do
        expect {
          delete list_comment_path(list, comment)
        }.to change(Comment, :count).by(-1)
      end

      it 'responds with turbo_stream format' do
        delete list_comment_path(list, comment),
               headers: { accept: 'text/vnd.turbo-stream.html' }

        expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      end

      it 'removes comment from DOM' do
        delete list_comment_path(list, comment),
               headers: { accept: 'text/vnd.turbo-stream.html' }

        expect(response.body).to include("turbo_stream.remove")
        expect(response.body).to include(comment.id)
      end

      it 'updates comments container' do
        delete list_comment_path(list, comment),
               headers: { accept: 'text/vnd.turbo-stream.html' }

        expect(response.body).to include("comments_container")
      end
    end

    context 'list owner' do
      before { sign_in list_owner }

      it 'allows list owner to delete any comment' do
        expect {
          delete list_comment_path(list, comment)
        }.to change(Comment, :count).by(-1)
      end
    end

    context 'unauthorized user' do
      let(:unauthorized_user) { create(:user, :verified) }

      before { sign_in unauthorized_user }

      it 'denies unauthorized user' do
        expect {
          delete list_comment_path(list, comment)
        }.not_to change(Comment, :count)

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with invalid comment' do
      it 'returns 404 for non-existent comment' do
        delete list_comment_path(list, 'invalid-id')

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with invalid list' do
      it 'returns 404 for non-existent list' do
        delete list_comment_path('invalid-id', comment)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE #destroy on ListItem' do
    let(:comment) { create(:comment, user: user, commentable: list_item) }

    before { sign_in user }

    context 'comment author' do
      it 'allows author to delete comment' do
        expect {
          delete list_list_item_comment_path(list, list_item, comment)
        }.to change(Comment, :count).by(-1)
      end

      it 'responds with turbo_stream format' do
        delete list_list_item_comment_path(list, list_item, comment),
               headers: { accept: 'text/vnd.turbo-stream.html' }

        expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      end
    end

    context 'authorization' do
      let(:unauthorized_user) { create(:user, :verified) }

      before { sign_in unauthorized_user }

      it 'denies unauthorized user' do
        expect {
          delete list_list_item_comment_path(list, list_item, comment)
        }.not_to change(Comment, :count)

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'parameter filtering' do
    before { sign_in user }

    it 'only allows content parameter' do
      list.collaborators.create!(user: user, permission: :comment)

      post list_comments_path(list),
           params: { comment: { content: 'Test', user_id: other_user.id } }

      comment = Comment.last
      expect(comment.user).to eq(user)
      expect(comment.user).not_to eq(other_user)
    end

    it 'sanitizes content input' do
      list.collaborators.create!(user: user, permission: :comment)

      post list_comments_path(list),
           params: { comment: { content: 'Test<script>alert("xss")</script>' } }

      comment = Comment.last
      expect(comment.content).to include('<script>')
    end
  end
end
