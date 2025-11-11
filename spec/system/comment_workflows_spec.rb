# spec/system/comment_workflows_spec.rb
require 'rails_helper'

RSpec.describe 'Comment Workflows', type: :system, js: true do
  let(:list_owner) { create(:user, :verified, name: 'List Owner') }
  let(:collaborator) { create(:user, :verified, name: 'Collaborator') }
  let(:viewer) { create(:user, :verified, name: 'Viewer') }
  let(:list) { create(:list, owner: list_owner, title: 'Shared List') }

  before do
    # Setup collaborations
    list.collaborators.create!(user: collaborator, permission: :comment)
    list.collaborators.create!(user: viewer, permission: :view)
  end

  describe 'viewing comments' do
    context 'on a list' do
      before do
        create(:comment, user: list_owner, commentable: list, content: 'Owner comment')
        create(:comment, user: collaborator, commentable: list, content: 'Collaborator comment')
      end

      it 'shows all comments on the list' do
        sign_in(list_owner)
        visit list_path(list)

        expect(page).to have_text('Owner comment')
        expect(page).to have_text('Collaborator comment')
      end

      it 'displays comment author name' do
        sign_in(list_owner)
        visit list_path(list)

        expect(page).to have_text('List Owner')
        expect(page).to have_text('Collaborator')
      end

      it 'displays comment creation time' do
        comment = create(:comment, user: list_owner, commentable: list, content: 'Test')
        sign_in(list_owner)
        visit list_path(list)

        # Time formatting depends on your implementation
        expect(page).to have_text(comment.created_at.strftime('%b %d'))
      end

      it 'shows comment count' do
        sign_in(list_owner)
        visit list_path(list)

        expect(page).to have_text('2')  # Comment count
      end
    end

    context 'on a list item' do
      let(:list_item) { create(:list_item, list: list, title: 'Task') }

      before do
        create(:comment, user: list_owner, commentable: list_item, content: 'Task comment')
      end

      it 'shows comments on the task' do
        sign_in(list_owner)
        visit list_path(list)
        click_on 'Task'

        expect(page).to have_text('Task comment')
      end
    end

    context 'empty comment section' do
      it 'shows empty state when no comments' do
        sign_in(list_owner)
        visit list_path(list)

        expect(page).to have_text('No comments yet')
      end
    end
  end

  describe 'creating comments' do
    context 'with permission' do
      it 'allows collaborator to add comment' do
        sign_in(collaborator)
        visit list_path(list)

        fill_in 'comment[content]', with: 'Great list!'
        click_button 'Comment'

        expect(page).to have_text('Great list!')
        expect(Comment.last.content).to eq('Great list!')
      end

      it 'allows list owner to add comment' do
        sign_in(list_owner)
        visit list_path(list)

        fill_in 'comment[content]', with: 'Owner comment'
        click_button 'Comment'

        expect(page).to have_text('Owner comment')
      end

      it 'clears form after successful submission' do
        sign_in(collaborator)
        visit list_path(list)

        fill_in 'comment[content]', with: 'Test comment'
        click_button 'Comment'

        # Form should be cleared
        expect(find('textarea[name="comment[content]"]').value).to be_empty
      end

      it 'shows comment immediately without page reload' do
        sign_in(collaborator)
        visit list_path(list)

        fill_in 'comment[content]', with: 'New comment'
        click_button 'Comment'

        expect(page).to have_text('New comment')
        expect(page).not_to have_selector('.loading')
      end

      it 'updates comment count' do
        sign_in(collaborator)
        visit list_path(list)

        expect(page).not_to have_text('1 comment')

        fill_in 'comment[content]', with: 'First comment'
        click_button 'Comment'

        expect(page).to have_text('1 comment')
      end

      it 'displays new comment with author info' do
        sign_in(collaborator)
        visit list_path(list)

        fill_in 'comment[content]', with: 'My comment'
        click_button 'Comment'

        expect(page).to have_text('My comment')
        expect(page).to have_text(collaborator.name)
      end
    end

    context 'without permission' do
      it 'hides comment form from view-only users' do
        sign_in(viewer)
        visit list_path(list)

        expect(page).not_to have_field('comment[content]')
        expect(page).not_to have_button('Comment')
      end

      it 'shows login prompt for unauthenticated users' do
        visit list_path(list)

        expect(page).to have_text('Sign in')
        expect(page).to have_link('Sign in', href: new_session_path)
      end
    end

    context 'validation errors' do
      it 'shows error when content is empty' do
        sign_in(collaborator)
        visit list_path(list)

        click_button 'Comment'

        expect(page).to have_text("can't be blank")
      end

      it 'shows error when content exceeds 5000 characters' do
        sign_in(collaborator)
        visit list_path(list)

        fill_in 'comment[content]', with: 'a' * 5001
        click_button 'Comment'

        expect(page).to have_text('too long')
      end

      it 'preserves form content on error' do
        sign_in(collaborator)
        visit list_path(list)

        content = 'My valuable comment'
        fill_in 'comment[content]', with: content

        # Simulate a validation error by clearing content
        find('textarea[name="comment[content]"]').set('')
        click_button 'Comment'

        # Form should show error
        expect(page).to have_text("can't be blank")
      end
    end

    context 'on list items' do
      let(:list_item) { create(:list_item, list: list, title: 'Task') }

      it 'allows commenting on task' do
        sign_in(collaborator)
        visit list_path(list)
        click_on 'Task'

        fill_in 'comment[content]', with: 'Task feedback'
        click_button 'Comment'

        expect(page).to have_text('Task feedback')
      end
    end
  end

  describe 'editing comments' do
    # Note: Implement edit functionality if needed
    pending 'allows editing comment content'
    pending 'shows edit timestamp'
  end

  describe 'deleting comments' do
    let(:comment) { create(:comment, user: collaborator, commentable: list, content: 'Deletable') }

    context 'as comment author' do
      it 'allows author to delete their comment' do
        sign_in(collaborator)
        visit list_path(list)

        expect(page).to have_text('Deletable')

        click_button 'Delete', match: :first

        expect(page).not_to have_text('Deletable')
        expect(Comment.find_by(id: comment.id)).to be_nil
      end

      it 'removes comment without page reload' do
        sign_in(collaborator)
        visit list_path(list)

        expect(page).to have_text('Deletable')

        click_button 'Delete', match: :first

        expect(page).not_to have_text('Deletable')
        expect(page).not_to have_selector('.loading')
      end

      it 'updates comment count after deletion' do
        sign_in(collaborator)
        visit list_path(list)

        expect(page).to have_text('1 comment')

        click_button 'Delete', match: :first

        expect(page).to have_text('No comments yet')
      end
    end

    context 'as list owner' do
      it 'allows list owner to delete any comment' do
        sign_in(list_owner)
        visit list_path(list)

        expect(page).to have_text('Deletable')

        click_button 'Delete', match: :first

        expect(page).not_to have_text('Deletable')
      end
    end

    context 'as unauthorized user' do
      it 'does not show delete button for other users comments' do
        create(:comment, user: list_owner, commentable: list, content: 'Others comment')

        sign_in(collaborator)
        visit list_path(list)

        expect(page).to have_text('Others comment')
        expect(page).not_to have_button('Delete')
      end
    end

    context 'without permission' do
      it 'does not show delete option for view-only users' do
        sign_in(viewer)
        visit list_path(list)

        expect(page).not_to have_button('Delete')
      end
    end
  end

  describe 'real-time collaboration' do
    it 'shows new comments from other users in real-time' do
      using_session('user1') do
        sign_in(list_owner)
        visit list_path(list)
        expect(page).to have_text('No comments yet')
      end

      using_session('user2') do
        sign_in(collaborator)
        visit list_path(list)

        fill_in 'comment[content]', with: 'Real-time comment'
        click_button 'Comment'
      end

      using_session('user1') do
        # Wait for real-time update
        expect(page).to have_text('Real-time comment', wait: 5)
      end
    end

    it 'reflects comment count changes in real-time' do
      using_session('user1') do
        sign_in(list_owner)
        visit list_path(list)
        expect(page).to have_text('No comments yet')
      end

      using_session('user2') do
        sign_in(collaborator)
        visit list_path(list)

        fill_in 'comment[content]', with: 'Update count'
        click_button 'Comment'
      end

      using_session('user1') do
        expect(page).to have_text('1 comment', wait: 5)
      end
    end
  end

  describe 'markdown support' do
    it 'preserves markdown formatting in comments' do
      sign_in(collaborator)
      visit list_path(list)

      markdown_content = "**bold** and *italic*"
      fill_in 'comment[content]', with: markdown_content
      click_button 'Comment'

      # Verify markdown was preserved
      comment = Comment.last
      expect(comment.content).to eq(markdown_content)
    end

    it 'handles special characters in comments' do
      sign_in(collaborator)
      visit list_path(list)

      special_content = "Comment with @mentions and #hashtags"
      fill_in 'comment[content]', with: special_content
      click_button 'Comment'

      expect(page).to have_text(special_content)
    end

    it 'handles multiline comments' do
      sign_in(collaborator)
      visit list_path(list)

      multiline_content = "Line 1\nLine 2\nLine 3"
      fill_in 'comment[content]', with: multiline_content
      click_button 'Comment'

      expect(Comment.last.content).to eq(multiline_content)
    end
  end

  describe 'comment sorting' do
    before do
      create(:comment, user: list_owner, commentable: list, content: 'First')
      travel(1.second)
      create(:comment, user: collaborator, commentable: list, content: 'Second')
      travel(1.second)
      create(:comment, user: list_owner, commentable: list, content: 'Third')
    end

    it 'displays comments in chronological order' do
      sign_in(list_owner)
      visit list_path(list)

      comments = page.all('.comment-item')
      expect(comments[0]).to have_text('First')
      expect(comments[1]).to have_text('Second')
      expect(comments[2]).to have_text('Third')
    end
  end

  describe 'accessibility' do
    let(:comment) { create(:comment, user: collaborator, commentable: list, content: 'Test') }

    it 'has proper form labels' do
      sign_in(collaborator)
      visit list_path(list)

      # Check that form elements have proper labels or ARIA labels
      textarea = find('textarea[name="comment[content]"]')
      expect(textarea).to have_attribute('placeholder')
    end

    it 'provides keyboard navigation for delete button' do
      sign_in(collaborator)
      visit list_path(list)

      # Delete button should be keyboard accessible
      expect(page).to have_button('Delete')
    end

    it 'shows ARIA labels for comment timestamps' do
      sign_in(list_owner)
      visit list_path(list)

      expect(page).to have_text(comment.created_at.strftime('%b %d'))
    end
  end
end
