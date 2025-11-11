RSpec.describe "Comment Workflows", type: :system, js: true do
  # Use let! (with bang) instead of let so variables are created before nested describes
  let!(:owner) { create(:user, :verified) }
  let!(:collaborator) { create(:user, :verified) }
  let!(:view_only_user) { create(:user, :verified) }
  let!(:other_user) { create(:user, :verified) }
  let!(:list) { create(:list, owner: owner) }
  let!(:list_item) { create(:list_item, list: list) }

  before do
    list.collaborators.create!(user: collaborator, permission: :write)
    list.collaborators.create!(user: view_only_user, permission: :read)
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
      end

      using_session("collaborator") do
        fill_in "comment[content]", with: "Great list!"
        click_button "Comment"
        expect(page).to have_text("Great list!")
      end

      using_session("owner") do
        expect(page).to have_text("Great list!", wait: 5)
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
      end

      using_session("collaborator") do
        fill_in "comment[content]", with: "New comment"
        click_button "Comment"
      end

      using_session("owner") do
        expect(page).to have_text("1 comment", wait: 5)
      end
    end
  end

  describe "viewing comments" do
    describe "on a list" do
      it "shows comment count" do
        create(:comment, commentable: list, user: collaborator, content: "Test comment")

        sign_in_with_ui(owner)
        visit list_path(list)

        expect(page).to have_text("1 comment")
      end

      it "shows all comments on the list" do
        create(:comment, commentable: list, user: collaborator, content: "First comment")
        create(:comment, commentable: list, user: owner, content: "Second comment")

        sign_in_with_ui(owner)
        visit list_path(list)

        expect(page).to have_text("First comment")
        expect(page).to have_text("Second comment")
      end

      it "displays comment author name" do
        create(:comment, commentable: list, user: collaborator, content: "Check this out")

        sign_in_with_ui(owner)
        visit list_path(list)

        expect(page).to have_text(collaborator.name)
      end

      it "displays comment creation time" do
        comment = create(:comment, commentable: list, user: collaborator, content: "Comment")

        sign_in_with_ui(owner)
        visit list_path(list)

        expect(page).to have_text(comment.created_at.strftime("%b %d"))
      end
    end

    describe "on a list item" do
      it "shows comments on the task" do
        create(:comment, commentable: list_item, user: collaborator, content: "Task comment")

        sign_in_with_ui(owner)
        visit list_path(list)
        click_link list_item.title

        expect(page).to have_text("Task comment")
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

  describe "deleting comments" do
    describe "as list owner" do
      it "allows list owner to delete any comment" do
        comment = create(:comment, commentable: list, user: collaborator, content: "To delete")

        sign_in_with_ui(owner)
        visit list_path(list)

        expect(page).to have_text("To delete")
        click_button "Delete", match: :first

        expect(page).not_to have_text("To delete")
      end
    end

    describe "as comment author" do
      it "allows author to delete their comment" do
        create(:comment, commentable: list, user: collaborator, content: "My comment")

        sign_in_with_ui(collaborator)
        visit list_path(list)

        click_button "Delete"

        expect(page).not_to have_text("My comment")
      end

      it "removes comment without page reload" do
        create(:comment, commentable: list, user: collaborator, content: "Comment to remove")

        sign_in_with_ui(collaborator)
        visit list_path(list)

        accept_alert do
          click_button "Delete"
        end

        expect(page).not_to have_text("Comment to remove")
      end

      it "updates comment count after deletion" do
        create(:comment, commentable: list, user: collaborator, content: "First")
        create(:comment, commentable: list, user: collaborator, content: "Second")

        sign_in_with_ui(collaborator)
        visit list_path(list)

        expect(page).to have_text("2 comments")

        click_button "Delete", match: :first

        expect(page).to have_text("1 comment")
      end
    end

    describe "without permission" do
      it "does not show delete option for view-only users" do
        create(:comment, commentable: list, user: collaborator, content: "Comment by collaborator")

        sign_in_with_ui(view_only_user)
        visit list_path(list)

        expect(page).to have_text("Comment by collaborator")
        expect(page).not_to have_button("Delete")
      end
    end

    describe "as unauthorized user" do
      it "does not show delete button for other users comments" do
        create(:comment, commentable: list, user: owner, content: "Owner's comment")

        sign_in_with_ui(collaborator)
        visit list_path(list)

        expect(page).to have_text("Owner's comment")
        expect(page).not_to have_button("Delete")
      end
    end
  end

  describe "editing comments" do
    it "shows edit timestamp" do
      comment = create(:comment, commentable: list, user: owner, content: "Original")
      comment.update(content: "Updated", updated_at: 1.hour.ago)

      sign_in_with_ui(owner)
      visit list_path(list)

      expect(page).to have_text("(edited)")
    end

    it "allows editing comment content" do
      create(:comment, commentable: list, user: owner, content: "Original text")

      sign_in_with_ui(owner)
      visit list_path(list)

      click_button "Edit"
      fill_in "comment[content]", with: "Updated text"
      click_button "Update"

      expect(page).to have_text("Updated text")
      expect(page).not_to have_text("Original text")
    end
  end

  describe "markdown support" do
    it "preserves markdown formatting in comments" do
      create(:comment, commentable: list, user: owner, content: "**bold text** and *italic*")

      sign_in_with_ui(owner)
      visit list_path(list)

      expect(page).to have_css("strong", text: "bold text")
      expect(page).to have_css("em", text: "italic")
    end

    it "handles multiline comments" do
      content = "First line\nSecond line\nThird line"
      create(:comment, commentable: list, user: owner, content: content)

      sign_in_with_ui(owner)
      visit list_path(list)

      expect(page).to have_text("First line")
      expect(page).to have_text("Second line")
      expect(page).to have_text("Third line")
    end

    it "handles special characters in comments" do
      content = "Special chars: <>&\"' and unicode: 你好 🎉"
      create(:comment, commentable: list, user: owner, content: content)

      sign_in_with_ui(owner)
      visit list_path(list)

      expect(page).to have_text("Special chars:")
      expect(page).to have_text("你好")
    end
  end

  describe "accessibility" do
    it "has proper form labels" do
      sign_in_with_ui(owner)
      visit list_path(list)

      expect(page).to have_label("comment[content]")
    end

    it "shows ARIA labels for comment timestamps" do
      create(:comment, commentable: list, user: owner, content: "Test")

      sign_in_with_ui(owner)
      visit list_path(list)

      expect(page).to have_xpath("//*[@aria-label]", text: /ago|AM|PM/)
    end

    it "provides keyboard navigation for delete button" do
      create(:comment, commentable: list, user: owner, content: "Test")

      sign_in_with_ui(owner)
      visit list_path(list)

      page.send_keys :tab

      expect(page).to have_focus_on_button("Delete")
    end
  end

  describe "creating comments" do
    describe "validation errors" do
      it "shows error when content is empty" do
        sign_in_with_ui(owner)
        visit list_path(list)

        click_button "Comment"

        expect(page).to have_text("can't be blank")
      end

      it "shows error when content exceeds 5000 characters" do
        sign_in_with_ui(owner)
        visit list_path(list)

        fill_in "comment[content]", with: "x" * 5001
        click_button "Comment"

        expect(page).to have_text("too long")
      end

      it "preserves form content on error" do
        sign_in_with_ui(owner)
        visit list_path(list)

        fill_in "comment[content]", with: "x" * 5001
        click_button "Comment"

        expect(page).to have_field("comment[content]", with: "x" * 5001)
      end
    end

    describe "without permission" do
      it "hides comment form from view-only users" do
        sign_in_with_ui(other_user)
        visit list_path(list)

        expect(page).not_to have_field("comment[content]")
      end

      it "shows login prompt for unauthenticated users" do
        visit list_path(list)

        expect(page).to have_link("Sign in")
      end
    end

    describe "with permission" do
      it "allows collaborator to add comment" do
        sign_in_with_ui(collaborator)
        visit list_path(list)

        fill_in "comment[content]", with: "Great work!"
        click_button "Comment"

        expect(page).to have_text("Great work!")
      end

      it "allows list owner to add comment" do
        sign_in_with_ui(owner)
        visit list_path(list)

        fill_in "comment[content]", with: "Owner comment"
        click_button "Comment"

        expect(page).to have_text("Owner comment")
      end

      it "displays new comment with author info" do
        sign_in_with_ui(collaborator)
        visit list_path(list)

        fill_in "comment[content]", with: "Test comment"
        click_button "Comment"

        expect(page).to have_text("Test comment")
        expect(page).to have_text(collaborator.name)
      end

      it "shows comment immediately without page reload" do
        sign_in_with_ui(owner)
        visit list_path(list)

        fill_in "comment[content]", with: "Instant comment"
        click_button "Comment"

        expect(page).to have_text("Instant comment")
        expect(page).to have_current_path(list_path(list))
      end

      it "clears form after successful submission" do
        sign_in_with_ui(owner)
        visit list_path(list)

        fill_in "comment[content]", with: "Test"
        click_button "Comment"

        expect(page).to have_field("comment[content]", with: "")
      end

      it "updates comment count" do
        sign_in_with_ui(owner)
        visit list_path(list)

        expect(page).to have_text("0 comments")

        fill_in "comment[content]", with: "First comment"
        click_button "Comment"

        expect(page).to have_text("1 comment")
      end
    end

    describe "on list items" do
      it "allows commenting on task" do
        sign_in_with_ui(owner)
        visit list_path(list)
        click_link list_item.title

        fill_in "comment[content]", with: "Task comment"
        click_button "Comment"

        expect(page).to have_text("Task comment")
      end
    end
  end

  describe "comment sorting" do
    it "displays comments in chronological order" do
      comment1 = create(:comment, commentable: list, user: owner, content: "First", created_at: 3.hours.ago)
      comment2 = create(:comment, commentable: list, user: collaborator, content: "Second", created_at: 2.hours.ago)
      comment3 = create(:comment, commentable: list, user: owner, content: "Third", created_at: 1.hour.ago)

      sign_in_with_ui(owner)
      visit list_path(list)

      comments = page.all(".comment")
      expect(comments[0]).to have_text("First")
      expect(comments[1]).to have_text("Second")
      expect(comments[2]).to have_text("Third")
    end
  end
end

RSpec::Matchers.define :have_focus_on_button do |button_text|
  match do |page|
    page.find_button(button_text) == page.driver.browser.switch_to.active_element
  end
end
