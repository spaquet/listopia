RSpec.describe "Comment Workflows", type: :system, js: true do
  let!(:owner) { create(:user, :verified) }
  let!(:collaborator) { create(:user, :verified) }
  let!(:list) { create(:list, owner: owner) }

  before do
    list.collaborators.create!(user: collaborator, permission: :comment)
  end

  describe "viewing comments" do
    describe "on a list" do
      it "shows comment count" do
        create(:comment, commentable: list, user: owner)

        sign_in_with_ui(owner)
        visit list_path(list)

        expect(page).to have_content("1")
      end

      it "displays comment author name" do
        create(:comment, commentable: list, user: owner)

        sign_in_with_ui(owner)
        visit list_path(list)

        expect(page).to have_text(owner.name)
      end

      it "shows all comments on the list" do
        create(:comment, commentable: list, user: owner, content: "Great list!")
        create(:comment, commentable: list, user: collaborator, content: "I agree!")

        sign_in_with_ui(owner)
        visit list_path(list)

        expect(page).to have_text("Great list!")
        expect(page).to have_text("I agree!")
      end

      it "displays comment creation time" do
        comment = create(:comment, commentable: list, user: owner)

        sign_in_with_ui(owner)
        visit list_path(list)

        expect(page).to have_content(comment.created_at.strftime("%b %d"))
      end
    end

    describe "on a list item" do
      it "shows comments on the task" do
        item = create(:list_item, list: list)
        create(:comment, commentable: item, user: owner)

        sign_in_with_ui(owner)
        visit list_path(list)

        expect(page).to have_text("1")
      end
    end

    describe "empty comment section" do
      it "shows empty state when no comments" do
        sign_in_with_ui(owner)
        visit list_path(list)

        expect(page).to have_text("No comments yet")
      end
    end
  end

  describe "creating comments" do
    describe "with permission" do
      it "displays new comment with author info" do
        sign_in_with_ui(collaborator)
        visit list_path(list)

        fill_in "Comment", with: "This is awesome!"
        click_button "Post Comment"

        expect(page).to have_text("This is awesome!")
        expect(page).to have_text(collaborator.name)
      end

      it "shows comment immediately without page reload" do
        sign_in_with_ui(collaborator)
        visit list_path(list)

        fill_in "Comment", with: "Instant comment"
        click_button "Post Comment"

        expect(page).to have_text("Instant comment")
      end

      it "allows collaborator to add comment" do
        sign_in_with_ui(collaborator)
        visit list_path(list)

        fill_in "Comment", with: "Collaborator comment"
        click_button "Post Comment"

        expect(page).to have_text("Collaborator comment")
      end

      it "allows list owner to add comment" do
        sign_in_with_ui(owner)
        visit list_path(list)

        fill_in "Comment", with: "Owner comment"
        click_button "Post Comment"

        expect(page).to have_text("Owner comment")
      end

      it "updates comment count" do
        sign_in_with_ui(collaborator)
        visit list_path(list)

        fill_in "Comment", with: "First comment"
        click_button "Post Comment"

        expect(page).to have_content("1")
      end

      it "clears form after successful submission" do
        sign_in_with_ui(collaborator)
        visit list_path(list)

        fill_in "Comment", with: "Test comment"
        click_button "Post Comment"

        expect(find("textarea[name='comment[content]']").value).to eq("")
      end
    end

    describe "without permission" do
      it "hides comment form from view-only users" do
        view_only_user = create(:user, :verified)
        list.collaborators.create!(user: view_only_user, permission: :view)

        sign_in_with_ui(view_only_user)
        visit list_path(list)

        expect(page).not_to have_field("Comment")
      end

      it "shows login prompt for unauthenticated users" do
        visit list_path(list)

        expect(page).to have_text("Sign In")
      end
    end

    describe "validation errors" do
      it "shows error when content is empty" do
        sign_in_with_ui(collaborator)
        visit list_path(list)

        click_button "Post Comment"

        expect(page).to have_text("can't be blank")
      end

      it "shows error when content exceeds 5000 characters" do
        sign_in_with_ui(collaborator)
        visit list_path(list)

        fill_in "Comment", with: "a" * 5001
        click_button "Post Comment"

        expect(page).to have_text("is too long")
      end

      it "preserves form content on error" do
        sign_in_with_ui(collaborator)
        visit list_path(list)

        content = "This should be preserved"
        fill_in "Comment", with: content
        click_button "Post Comment"

        expect(find("textarea[name='comment[content]']").value).to include(content)
      end
    end

    describe "on list items" do
      it "allows commenting on task" do
        item = create(:list_item, list: list)

        sign_in_with_ui(collaborator)
        visit list_path(list)

        fill_in "Comment", with: "Task comment"
        click_button "Post Comment"

        expect(page).to have_text("Task comment")
      end
    end
  end

  describe "real-time collaboration" do
    it "shows new comments from other users in real-time" do
      using_session("owner") do
        sign_in_with_ui(owner)
        visit list_path(list)
      end

      using_session("collaborator") do
        sign_in_with_ui(collaborator)
        visit list_path(list)

        fill_in "Comment", with: "Realtime comment"
        click_button "Post Comment"
      end

      using_session("owner") do
        expect(page).to have_text("Realtime comment", wait: 5)
      end
    end

    it "reflects comment count changes in real-time" do
      using_session("owner") do
        sign_in_with_ui(owner)
        visit list_path(list)
      end

      using_session("collaborator") do
        sign_in_with_ui(collaborator)
        visit list_path(list)

        fill_in "Comment", with: "Count this"
        click_button "Post Comment"
      end

      using_session("owner") do
        expect(page).to have_text("1", wait: 5)
      end
    end
  end

  describe "deleting comments" do
    describe "as comment author" do
      it "allows author to delete their comment" do
        comment = create(:comment, commentable: list, user: collaborator)

        sign_in_with_ui(collaborator)
        visit list_path(list)

        within("[data-comment-id='#{comment.id}']") do
          click_button "Delete"
        end

        expect(page).not_to have_text(comment.content)
      end

      it "removes comment without page reload" do
        comment = create(:comment, commentable: list, user: collaborator)

        sign_in_with_ui(collaborator)
        visit list_path(list)

        within("[data-comment-id='#{comment.id}']") do
          click_button "Delete"
        end

        expect(page).to have_current_path(list_path(list))
      end

      it "updates comment count after deletion" do
        create(:comment, commentable: list, user: collaborator)

        sign_in_with_ui(collaborator)
        visit list_path(list)

        within("div[data-comment]") do
          click_button "Delete"
        end

        expect(page).to have_content("0")
      end
    end

    describe "as list owner" do
      it "allows list owner to delete any comment" do
        comment = create(:comment, commentable: list, user: collaborator)

        sign_in_with_ui(owner)
        visit list_path(list)

        within("[data-comment-id='#{comment.id}']") do
          click_button "Delete"
        end

        expect(page).not_to have_text(comment.content)
      end
    end

    describe "without permission" do
      it "does not show delete option for view-only users" do
        comment = create(:comment, commentable: list, user: owner)
        view_only_user = create(:user, :verified)
        list.collaborators.create!(user: view_only_user, permission: :view)

        sign_in_with_ui(view_only_user)
        visit list_path(list)

        expect(page).not_to have_button("Delete")
      end
    end

    describe "as unauthorized user" do
      it "does not show delete button for other users comments" do
        comment = create(:comment, commentable: list, user: owner)
        other_user = create(:user, :verified)
        list.collaborators.create!(user: other_user, permission: :comment)

        sign_in_with_ui(other_user)
        visit list_path(list)

        expect(page).not_to have_button("Delete")
      end
    end
  end

  describe "editing comments" do
    it "allows editing comment content" do
      comment = create(:comment, commentable: list, user: collaborator)

      sign_in_with_ui(collaborator)
      visit list_path(list)

      within("[data-comment-id='#{comment.id}']") do
        click_button "Edit"
        fill_in "content", with: "Updated content"
        click_button "Save"
      end

      expect(page).to have_text("Updated content")
    end

    it "shows edit timestamp" do
      comment = create(:comment, commentable: list, user: collaborator)

      sign_in_with_ui(collaborator)
      visit list_path(list)

      within("[data-comment-id='#{comment.id}']") do
        click_button "Edit"
        fill_in "content", with: "Updated"
        click_button "Save"
      end

      expect(page).to have_text("(edited)")
    end
  end

  describe "markdown support" do
    it "preserves markdown formatting in comments" do
      sign_in_with_ui(collaborator)
      visit list_path(list)

      fill_in "Comment", with: "# Heading\n**bold** and *italic*"
      click_button "Post Comment"

      expect(page).to have_css("strong", text: "bold")
      expect(page).to have_css("em", text: "italic")
    end

    it "handles multiline comments" do
      sign_in_with_ui(collaborator)
      visit list_path(list)

      fill_in "Comment", with: "Line 1\nLine 2\nLine 3"
      click_button "Post Comment"

      expect(page).to have_text("Line 1")
      expect(page).to have_text("Line 2")
      expect(page).to have_text("Line 3")
    end

    it "handles special characters in comments" do
      sign_in_with_ui(collaborator)
      visit list_path(list)

      fill_in "Comment", with: "Test & <special> \"characters\" 'quoted'"
      click_button "Post Comment"

      expect(page).to have_text("Test & <special>")
    end
  end

  describe "comment sorting" do
    it "displays comments in chronological order" do
      create(:comment, commentable: list, user: owner, content: "First", created_at: 1.hour.ago)
      create(:comment, commentable: list, user: collaborator, content: "Second", created_at: 30.minutes.ago)
      create(:comment, commentable: list, user: owner, content: "Third", created_at: Time.current)

      sign_in_with_ui(owner)
      visit list_path(list)

      first_comment = page.find_all("[data-comment]")[0]
      second_comment = page.find_all("[data-comment]")[1]
      third_comment = page.find_all("[data-comment]")[2]

      expect(first_comment).to have_text("First")
      expect(second_comment).to have_text("Second")
      expect(third_comment).to have_text("Third")
    end
  end

  describe "accessibility" do
    it "has proper form labels" do
      sign_in_with_ui(collaborator)
      visit list_path(list)

      expect(page).to have_label("Comment")
    end

    it "shows ARIA labels for comment timestamps" do
      create(:comment, commentable: list, user: owner)

      sign_in_with_ui(owner)
      visit list_path(list)

      expect(page).to have_css("[aria-label*='Posted']")
    end

    it "provides keyboard navigation for delete button" do
      create(:comment, commentable: list, user: collaborator)

      sign_in_with_ui(collaborator)
      visit list_path(list)

      delete_button = find_button("Delete")

      expect(delete_button).to be_visible
    end
  end
end
