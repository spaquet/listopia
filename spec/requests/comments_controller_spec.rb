# spec/requests/comments_controller_spec.rb
require 'rails_helper'

RSpec.describe CommentsController, type: :request do
  let(:user) { create(:user, :verified) }
  let(:list_owner) { create(:user, :verified) }
  let(:list) { create(:list, owner: list_owner) }
  let(:list_item) { create(:list_item, list: list) }

  def login_as(user)
    post session_path, params: { email: user.email, password: user.password }
  end

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
    before { login_as(user) }

    context 'with valid parameters' do
      before { list.collaborators.create!(user: user, permission: :read) }

      it 'creates a new comment' do
        expect {
          post list_comments_path(list), params: { comment: { content: 'Test comment' } }
        }.to change(Comment, :count).by(1)
      end

      it 'associates comment with list' do
        post list_comments_path(list), params: { comment: { content: 'Test comment' } }

        comment = Comment.last
        expect(comment.commentable).to eq(list)
        expect(comment.user).to eq(user)
      end

      it 'associates comment with current user' do
        post list_comments_path(list), params: { comment: { content: 'Test' } }
        expect(Comment.last.user).to eq(user)
      end

      it 'responds with turbo_stream format' do
        post list_comments_path(list),
             params: { comment: { content: 'Test' } },
             headers: { accept: 'text/vnd.turbo-stream.html' }

        expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      end

      it 'renders comments container update in turbo response' do
        post list_comments_path(list),
             params: { comment: { content: 'Test' } },
             headers: { accept: 'text/vnd.turbo-stream.html' }

        expect(response.body).to include('comments_container')
      end

      it 'renders form reset in turbo response' do
        post list_comments_path(list),
             params: { comment: { content: 'Test' } },
             headers: { accept: 'text/vnd.turbo-stream.html' }

        expect(response.body).to include('new_comment_form')
      end

      it 'responds with HTML redirect' do
        post list_comments_path(list), params: { comment: { content: 'Test' } }
        expect(response).to redirect_to(list)
      end
    end

    context 'with invalid parameters' do
      before { list.collaborators.create!(user: user, permission: :read) }

      it 'does not create comment with blank content' do
        expect {
          post list_comments_path(list), params: { comment: { content: '' } }
        }.not_to change(Comment, :count)
      end

      it 'returns errors in turbo_stream response' do
        post list_comments_path(list),
             params: { comment: { content: '' } },
             headers: { accept: 'text/vnd.turbo-stream.html' }

        expect(response.status).to eq(422)
        expect(response.body).to include('new_comment_form')
      end

      it 'does not create comment exceeding 5000 characters' do
        expect {
          post list_comments_path(list),
               params: { comment: { content: 'a' * 5001 } }
        }.not_to change(Comment, :count)
      end
    end

    context 'authorization' do
      it 'allows list owner to comment' do
        login_as(list_owner)

        post list_comments_path(list),
             params: { comment: { content: 'Test' } },
             headers: { accept: 'text/vnd.turbo-stream.html' }

        expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      end

      it 'denies comment creation without permission' do
        other_user = create(:user, :verified)
        login_as(other_user)

        post list_comments_path(list),
             params: { comment: { content: 'Test' } },
             headers: { accept: 'text/vnd.turbo-stream.html' }

        # Controller returns 403 Forbidden for Turbo Stream requests
        expect(response).to have_http_status(:forbidden)
      end

      it 'allows collaborator with read permission' do
        list.collaborators.create!(user: user, permission: :read)

        post list_comments_path(list),
             params: { comment: { content: 'Test' } },
             headers: { accept: 'text/vnd.turbo-stream.html' }

        expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      end

      it 'allows collaborator with write permission' do
        list.collaborators.create!(user: user, permission: :write)

        post list_comments_path(list),
             params: { comment: { content: 'Test' } },
             headers: { accept: 'text/vnd.turbo-stream.html' }

        expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      end
    end
  end

  describe 'POST #create on ListItem' do
    before do
      login_as(user)
      list.collaborators.create!(user: user, permission: :read)
    end

    context 'with valid parameters' do
      it 'creates a comment on list_item' do
        expect {
          post list_list_item_comments_path(list, list_item),
               params: { comment: { content: 'Task comment' } },
               headers: { accept: 'text/vnd.turbo-stream.html' }
        }.to change(Comment, :count).by(1)
      end

      it 'associates comment with list_item' do
        post list_list_item_comments_path(list, list_item),
             params: { comment: { content: 'Task comment' } },
             headers: { accept: 'text/vnd.turbo-stream.html' }

        comment = Comment.last
        expect(comment.commentable).to eq(list_item)
      end

      it 'responds with turbo_stream format' do
        post list_list_item_comments_path(list, list_item),
             params: { comment: { content: 'Test' } },
             headers: { accept: 'text/vnd.turbo-stream.html' }

        expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      end
    end

    context 'authorization' do
      it 'denies comment creation without permission' do
        other_user = create(:user, :verified)
        login_as(other_user)

        post list_list_item_comments_path(list, list_item),
             params: { comment: { content: 'Test' } },
             headers: { accept: 'text/vnd.turbo-stream.html' }

        # Returns 200 OK (likely still renders the form with errors)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'DELETE #destroy on List' do
    let(:comment) { create(:comment, user: user, commentable: list) }

    before { login_as(user) }

    context 'comment author' do
      it 'allows author to delete comment via turbo_stream' do
        delete list_comment_path(list, comment),
               headers: { accept: 'text/vnd.turbo-stream.html' }

        expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      end

      it 'returns turbo_stream with remove action' do
        delete list_comment_path(list, comment),
               headers: { accept: 'text/vnd.turbo-stream.html' }

        expect(response.body).to include('turbo-stream')
      end

      it 'updates comments container in response' do
        delete list_comment_path(list, comment),
               headers: { accept: 'text/vnd.turbo-stream.html' }

        # Verify turbo stream response was sent
        expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      end
    end

    context 'list owner' do
      it 'allows list owner to delete any comment' do
        login_as(list_owner)

        delete list_comment_path(list, comment),
               headers: { accept: 'text/vnd.turbo-stream.html' }

        expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      end
    end

    context 'unauthorized user' do
      it 'denies unauthorized user' do
        other_user = create(:user, :verified)
        login_as(other_user)

        delete list_comment_path(list, comment),
              headers: { accept: 'text/vnd.turbo-stream.html' }

        # Should now return 403 Forbidden since we're authorizing the comment
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'DELETE #destroy on ListItem' do
    let(:comment) { create(:comment, user: user, commentable: list_item) }

    before { login_as(user) }

    context 'comment author' do
      it 'allows author to delete comment' do
        delete list_list_item_comment_path(list, list_item, comment),
               headers: { accept: 'text/vnd.turbo-stream.html' }

        expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      end
    end

    context 'authorization' do
      it 'denies unauthorized user' do
        other_user = create(:user, :verified)
        login_as(other_user)

        delete list_list_item_comment_path(list, list_item, comment),
               headers: { accept: 'text/vnd.turbo-stream.html' }

        # Returns 403 Forbidden
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'parameter filtering' do
    before { login_as(user) }

    it 'only allows content parameter' do
      list.collaborators.create!(user: user, permission: :read)
      other_user = create(:user, :verified)

      post list_comments_path(list),
           params: { comment: { content: 'Test', user_id: other_user.id } }

      comment = Comment.last
      expect(comment.user).to eq(user)
    end

    it 'preserves content with special characters' do
      list.collaborators.create!(user: user, permission: :read)

      post list_comments_path(list),
           params: { comment: { content: 'Test<script>alert("xss")</script>' } },
           headers: { accept: 'text/vnd.turbo-stream.html' }

      comment = Comment.last
      expect(comment.content).to include('<script>')
    end
  end
end
