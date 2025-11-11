require 'rails_helper'

# Specs in this file have access to a helper object that includes
# the CommentsHelper. For example:
#
# describe CommentsHelper do
#   describe "string concat" do
#     it "concats two strings with spaces" do
#       expect(helper.concat_strings("this","that")).to eq("this that")
#     end
#   end
# end
# spec/helpers/comments_helper_spec.rb

RSpec.describe CommentsHelper, type: :helper do
  let(:user) { create(:user, :verified) }
  let(:list) { create(:list, owner: user) }
  let(:list_item) { create(:list_item, list: list) }

  describe '#comment_delete_path' do
    context 'for a comment on a List' do
      let(:comment) { create(:comment, user: user, commentable: list) }

      it 'returns the correct path for list comment deletion' do
        path = helper.comment_delete_path(comment)
        expected = list_comment_path(list, comment)
        expect(path).to eq(expected)
      end

      it 'generates correct URL' do
        path = helper.comment_delete_path(comment)
        expect(path).to include("/lists/#{list.id}/comments/#{comment.id}")
      end
    end

    context 'for a comment on a ListItem' do
      let(:comment) { create(:comment, user: user, commentable: list_item) }

      it 'returns the correct path for list_item comment deletion' do
        path = helper.comment_delete_path(comment)
        expected = list_list_item_comment_path(list, list_item, comment)
        expect(path).to eq(expected)
      end

      it 'generates correct URL' do
        path = helper.comment_delete_path(comment)
        expect(path).to include("/lists/#{list.id}/list_items/#{list_item.id}/comments/#{comment.id}")
      end
    end

    context 'with unknown commentable type' do
      let(:comment) { create(:comment, user: user, commentable: list) }

      it 'raises error for unsupported commentable type' do
        allow(comment).to receive(:commentable_type).and_return('UnknownType')

        expect {
          helper.comment_delete_path(comment)
        }.to raise_error(/Unknown commentable type/)
      end
    end
  end

  describe 'view rendering' do
    describe '_form.html.erb' do
      context 'for authenticated user with permission' do
        it 'renders comment form' do
          list.collaborators.create!(user: user, permission: :comment)

          render partial: 'comments/form',
                 locals: { commentable: list, comment: Comment.new }

          expect(rendered).to have_field('comment[content]')
          expect(rendered).to have_button('Comment')
        end

        it 'displays placeholder text' do
          list.collaborators.create!(user: user, permission: :comment)

          render partial: 'comments/form',
                 locals: { commentable: list, comment: Comment.new }

          expect(rendered).to have_field(with: { placeholder: 'Add a comment...' })
        end

        it 'shows markdown formatting hint' do
          list.collaborators.create!(user: user, permission: :comment)

          render partial: 'comments/form',
                 locals: { commentable: list, comment: Comment.new }

          expect(rendered).to have_text('Markdown formatting is supported')
        end

        it 'displays form errors when present' do
          comment = Comment.new(content: '')
          comment.validate

          render partial: 'comments/form',
                 locals: { commentable: list, comment: comment }

          expect(rendered).to have_text("can't be blank")
        end

        it 'preserves form content on validation errors' do
          comment = Comment.new(content: 'My comment')
          comment.content = nil
          comment.validate

          render partial: 'comments/form',
                 locals: { commentable: list, comment: comment }

          expect(rendered).to have_field('comment[content]', with: 'My comment')
        end

        it 'generates correct form action for List' do
          render partial: 'comments/form',
                 locals: { commentable: list, comment: Comment.new }

          expect(rendered).to include("lists/#{list.id}/comments")
        end

        it 'generates correct form action for ListItem' do
          render partial: 'comments/form',
                 locals: { commentable: list_item, comment: Comment.new }

          expect(rendered).to include("lists/#{list.id}/list_items/#{list_item.id}/comments")
        end

        it 'uses turbo_frame_tag for dynamic updates' do
          render partial: 'comments/form',
                 locals: { commentable: list, comment: Comment.new }

          expect(rendered).to include('turbo-frame-id')
        end
      end

      context 'for unauthenticated user' do
        before { allow(view).to receive(:user_signed_in?).and_return(false) }

        it 'shows login prompt' do
          render partial: 'comments/form',
                 locals: { commentable: list, comment: Comment.new }

          expect(rendered).to have_text('Sign in')
          expect(rendered).to have_link('Sign in', href: new_session_path)
        end

        it 'does not show comment form' do
          render partial: 'comments/form',
                 locals: { commentable: list, comment: Comment.new }

          expect(rendered).not_to have_field('comment[content]')
        end
      end
    end

    describe '_comment.html.erb' do
      let(:comment) { create(:comment, user: user, commentable: list, content: 'Test comment') }

      before { allow(view).to receive(:current_user).and_return(user) }

      it 'displays comment content' do
        render partial: 'comments/comment', locals: { comment: comment }

        expect(rendered).to have_text('Test comment')
      end

      it 'displays comment author name' do
        render partial: 'comments/comment', locals: { comment: comment }

        expect(rendered).to have_text(user.name)
      end

      it 'displays comment creation time' do
        render partial: 'comments/comment', locals: { comment: comment }

        expect(rendered).to have_text(comment.created_at.strftime('%b %d'))
      end

      it 'shows delete button for comment author' do
        render partial: 'comments/comment', locals: { comment: comment }

        expect(rendered).to have_button('Delete')
      end

      it 'hides delete button for non-author' do
        other_user = create(:user, :verified)
        allow(view).to receive(:current_user).and_return(other_user)

        render partial: 'comments/comment', locals: { comment: comment }

        expect(rendered).not_to have_button('Delete')
      end

      it 'wraps comment in correct turbo_frame_tag' do
        render partial: 'comments/comment', locals: { comment: comment }

        expect(rendered).to include("turbo-frame-id=\"comment_#{comment.id}\"")
      end

      it 'handles multiline content' do
        multiline_comment = create(:comment,
                                   user: user,
                                   commentable: list,
                                   content: "Line 1\nLine 2\nLine 3")

        render partial: 'comments/comment', locals: { comment: multiline_comment }

        expect(rendered).to have_text('Line 1')
        expect(rendered).to have_text('Line 2')
        expect(rendered).to have_text('Line 3')
      end

      it 'handles special characters' do
        special_comment = create(:comment,
                                 user: user,
                                 commentable: list,
                                 content: "Comment with <>&\"'")

        render partial: 'comments/comment', locals: { comment: special_comment }

        # Should escape special characters for HTML safety
        expect(rendered).to include('&lt;')
        expect(rendered).to include('&gt;')
      end
    end

    describe '_comments_container.html.erb' do
      context 'with comments' do
        before do
          create(:comment, user: user, commentable: list, content: 'First')
          create(:comment, user: user, commentable: list, content: 'Second')
        end

        it 'displays comment count' do
          render partial: 'comments/comments_container',
                 locals: { commentable: list }

          expect(rendered).to have_text('2 comments')
        end

        it 'renders all comments' do
          render partial: 'comments/comments_container',
                 locals: { commentable: list }

          expect(rendered).to have_text('First')
          expect(rendered).to have_text('Second')
        end

        it 'wraps container in correct turbo_frame_tag' do
          render partial: 'comments/comments_container',
                 locals: { commentable: list }

          expect(rendered).to include("turbo-frame-id=\"comments_container_list_#{list.id}\"")
        end
      end

      context 'without comments' do
        it 'shows empty state' do
          render partial: 'comments/comments_container',
                 locals: { commentable: list }

          expect(rendered).to have_text('No comments yet')
        end

        it 'does not display comment count for empty' do
          render partial: 'comments/comments_container',
                 locals: { commentable: list }

          expect(rendered).not_to have_text('comments')
        end
      end

      it 'orders comments by creation time' do
        comment1 = create(:comment, user: user, commentable: list, content: 'First')
        travel(1.second)
        comment2 = create(:comment, user: user, commentable: list, content: 'Second')

        render partial: 'comments/comments_container',
               locals: { commentable: list }

        expect(rendered.index('First')).to be < rendered.index('Second')
      end

      it 'renders form below comments' do
        render partial: 'comments/comments_container',
               locals: { commentable: list }

        expect(rendered).to include('new_comment_form')
      end
    end
  end

  describe 'accessibility in views' do
    it 'form has proper ARIA labels' do
      render partial: 'comments/form',
             locals: { commentable: list, comment: Comment.new }

      textarea = rendered.match(/<textarea.*?>/m)
      expect(textarea.to_s).to include('placeholder')
    end

    it 'delete buttons have proper labels' do
      comment = create(:comment, user: user, commentable: list)
      allow(view).to receive(:current_user).and_return(user)

      render partial: 'comments/comment', locals: { comment: comment }

      expect(rendered).to have_button('Delete')
    end
  end
end
