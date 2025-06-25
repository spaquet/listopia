# spec/models/model_integration_spec.rb
require 'rails_helper'

RSpec.describe "Model Integration", type: :model do
  describe "User, List, ListItem, and ListCollaboration integration" do
    let(:owner) { create(:user, :verified, name: "Alice Owner") }
    let(:collaborator) { create(:user, :verified, name: "Bob Collaborator") }
    let(:viewer) { create(:user, :verified, name: "Charlie Viewer") }

    describe "complete collaboration workflow" do
      it "supports full list collaboration lifecycle" do
        # 1. Owner creates a list
        list = create(:list, :active, owner: owner, title: "Team Project")
        expect(list.readable_by?(owner)).to be true
        expect(list.collaboratable_by?(owner)).to be true

        # 2. Owner adds items to the list
        task1 = create(:list_item, :task, :high_priority, list: list, title: "Setup database")
        task2 = create(:list_item, :task, :medium_priority, list: list, title: "Write tests")
        note = create(:list_item, :note, list: list, title: "Meeting notes")

        expect(list.list_items.count).to eq(3)
        expect(list.completion_percentage).to eq(0.0)

        # 3. Owner invites collaborators
        collab1 = list.add_collaborator(collaborator, permission: 'collaborate')
        collab2 = list.add_collaborator(viewer, permission: 'read')

        expect(collab1.permission_collaborate?).to be true
        expect(collab2.permission_read?).to be true

        # 4. Check access permissions
        expect(list.readable_by?(collaborator)).to be true
        expect(list.collaboratable_by?(collaborator)).to be true
        expect(list.readable_by?(viewer)).to be true
        expect(list.collaboratable_by?(viewer)).to be false

        # 5. Collaborator completes tasks
        expect(task1.editable_by?(collaborator)).to be true
        expect(task1.editable_by?(viewer)).to be false

        task1.toggle_completion!
        expect(task1.completed?).to be true
        expect(task1.completed_at).to be_present

        # 6. Check progress updates
        expect(list.completion_percentage).to eq(33.33) # 1 of 3 completed

        # 7. Assign tasks to specific users
        task2.update!(assigned_user: collaborator)
        expect(task2.editable_by?(collaborator)).to be true

        # 8. Complete all tasks
        task2.toggle_completion!
        note.update!(completed: true)

        expect(list.completion_percentage).to eq(100.0)

        # 9. List status management
        list.status_completed!
        expect(list.status_completed?).to be true
      end
    end

    describe "public list sharing" do
      it "handles public list access correctly" do
        # Create public list
        public_list = create(:list, :public, :active, owner: owner)
        expect(public_list.is_public?).to be true
        expect(public_list.public_slug).to be_present

        # Add some items
        create_list(:list_item, 3, list: public_list)

        # Non-authenticated access
        expect(public_list.readable_by?(nil)).to be false # Still requires user for readable_by?

        # Any authenticated user can read
        random_user = create(:user, :verified)
        expect(public_list.readable_by?(random_user)).to be true
        expect(public_list.collaboratable_by?(random_user)).to be false

        # Only owner and explicit collaborators can edit
        expect(public_list.collaboratable_by?(owner)).to be true
      end
    end

    describe "user accessible lists" do
      it "correctly aggregates all user-accessible lists" do
        # User owns some lists
        owned_list1 = create(:list, owner: owner)
        owned_list2 = create(:list, owner: owner)

        # User collaborates on other lists
        other_owner = create(:user, :verified)
        collab_list1 = create(:list, owner: other_owner)
        collab_list2 = create(:list, owner: other_owner)

        create(:list_collaboration, list: collab_list1, user: owner, permission: 'read')
        create(:list_collaboration, list: collab_list2, user: owner, permission: 'collaborate')

        # Lists user has no access to
        create(:list, owner: other_owner) # No collaboration

        accessible = owner.accessible_lists
        expect(accessible).to contain_exactly(owned_list1, owned_list2, collab_list1, collab_list2)
      end
    end

    describe "item assignment and permissions" do
      it "handles complex assignment scenarios" do
        list = create(:list, owner: owner)

        # Add collaborators with different permissions
        editor = create(:user, :verified)
        reader = create(:user, :verified)
        assignee = create(:user, :verified)

        create(:list_collaboration, list: list, user: editor, permission: 'collaborate')
        create(:list_collaboration, list: list, user: reader, permission: 'read')
        # Assignee is not a collaborator but will be assigned tasks

        # Create item assigned to non-collaborator
        assigned_item = create(:list_item, list: list, assigned_user: assignee)

        # Check editing permissions
        expect(assigned_item.editable_by?(owner)).to be true        # Owner can edit
        expect(assigned_item.editable_by?(editor)).to be true       # Collaborator can edit
        expect(assigned_item.editable_by?(reader)).to be false      # Reader cannot edit
        expect(assigned_item.editable_by?(assignee)).to be true     # Assignee can edit

        # Assigned user can complete their own tasks
        assigned_item.toggle_completion!
        expect(assigned_item.completed?).to be true
      end
    end

    describe "overdue item tracking" do
      it "correctly identifies overdue items across lists" do
        list1 = create(:list, owner: owner)
        list2 = create(:list, owner: owner)

        # Create items with various due dates
        overdue_item1 = create(:list_item, :overdue, list: list1, completed: false)
        overdue_item2 = create(:list_item, list: list2, due_date: 2.days.ago, completed: false)
        completed_overdue = create(:list_item, :overdue, :completed, list: list1)
        future_item = create(:list_item, :due_tomorrow, list: list1)
        no_due_date = create(:list_item, list: list2, due_date: nil)

        # Check overdue status
        expect(overdue_item1.overdue?).to be true
        expect(overdue_item2.overdue?).to be true
        expect(completed_overdue.overdue?).to be false  # Completed items are not overdue
        expect(future_item.overdue?).to be false        # Future due date
        expect(no_due_date.overdue?).to be false        # No due date

        # Test through user's accessible lists
        accessible_lists = owner.accessible_lists.includes(:list_items)
        all_items = accessible_lists.flat_map(&:list_items)
        overdue_items = all_items.select(&:overdue?)

        expect(overdue_items).to contain_exactly(overdue_item1, overdue_item2)
      end
    end

    describe "list completion statistics" do
      it "accurately calculates completion across different scenarios" do
        list = create(:list, owner: owner)

        # Empty list
        expect(list.completion_percentage).to eq(0)

        # Add items progressively
        item1 = create(:list_item, list: list, completed: false)
        expect(list.completion_percentage).to eq(0)

        item2 = create(:list_item, list: list, completed: true)
        expect(list.completion_percentage).to eq(50.0)

        item3 = create(:list_item, list: list, completed: false)
        expect(list.completion_percentage).to eq(33.33) # 1 of 3

        # Complete all items
        item1.update!(completed: true)
        item3.update!(completed: true)
        expect(list.completion_percentage).to eq(100.0)
      end
    end

    describe "collaboration permission changes" do
      it "handles permission upgrades and downgrades" do
        list = create(:list, owner: owner)
        collaboration = create(:list_collaboration, :read_permission, list: list, user: collaborator)

        item = create(:list_item, list: list)

        # Initially read-only
        expect(list.collaboratable_by?(collaborator)).to be false
        expect(item.editable_by?(collaborator)).to be false

        # Upgrade to editor
        collaboration.update!(permission: 'collaborate')
        list.reload # Ensure association is refreshed

        expect(list.collaboratable_by?(collaborator)).to be true
        expect(item.editable_by?(collaborator)).to be true

        # Downgrade back to reader
        collaboration.update!(permission: 'read')
        list.reload

        expect(list.collaboratable_by?(collaborator)).to be false
        expect(item.editable_by?(collaborator)).to be false
      end
    end

    describe "pending invitation workflow" do
      it "handles the complete invitation acceptance flow" do
        list = create(:list, owner: owner)
        invite_email = 'newuser@example.com'

        # Create pending invitation
        pending_collab = create(:list_collaboration, :pending,
                               list: list,
                               email: invite_email,
                               permission: 'collaborate')

        expect(pending_collab.pending?).to be true
        expect(pending_collab.accepted?).to be false
        expect(pending_collab.display_email).to eq(invite_email)
        expect(pending_collab.display_name).to eq(invite_email)

        # New user signs up with invited email
        new_user = create(:user, :verified, email: invite_email)

        # Accept invitation
        pending_collab.update!(user: new_user, email: nil)

        expect(pending_collab.pending?).to be false
        expect(pending_collab.accepted?).to be true
        expect(pending_collab.display_email).to eq(new_user.email)
        expect(pending_collab.display_name).to eq(new_user.name)

        # Verify access
        expect(list.collaboratable_by?(new_user)).to be true
      end
    end

    describe "cascade deletions" do
      it "properly handles deletions throughout the hierarchy" do
        list = create(:list, owner: owner)
        collaboration = create(:list_collaboration, list: list, user: collaborator)
        items = create_list(:list_item, 3, list: list)
        session = create(:session, user: owner)

        # Verify initial state
        expect(List.count).to eq(1)
        expect(ListCollaboration.count).to eq(1)
        expect(ListItem.count).to eq(3)
        expect(Session.count).to eq(1)

        # Delete list should remove items and collaborations
        list.destroy
        expect(List.count).to eq(0)
        expect(ListCollaboration.count).to eq(0)
        expect(ListItem.count).to eq(0)
        expect(Session.count).to eq(1) # Sessions should remain

        # Recreate for user deletion test
        list = create(:list, owner: owner)
        create(:list_collaboration, list: list, user: collaborator)
        create_list(:list_item, 2, list: list)

        # Delete user should remove their lists, collaborations, and sessions
        initial_lists = List.count
        initial_collabs = ListCollaboration.count
        initial_items = ListItem.count

        owner.destroy

        expect(List.count).to eq(0) # Owner's lists deleted
        expect(ListCollaboration.count).to eq(0) # Collaborations deleted with list
        expect(ListItem.count).to eq(0) # Items deleted with list
        expect(Session.count).to eq(0) # User's sessions deleted
      end
    end
  end

  describe "Authentication integration" do
    let(:user) { create(:user, :verified) }

    describe "magic link and session workflow" do
      it "handles complete authentication flow" do
        # Generate magic link
        token = user.generate_magic_link_token
        expect(token).to be_present

        # Verify token is valid
        found_user = User.find_by_magic_link_token(token)
        expect(found_user).to eq(user)

        # Create session after authentication
        session = create(:session, user: user)
        expect(session.active?).to be true
        expect(session.user).to eq(user)

        # Use session for access
        found_session = Session.find_by_token(session.session_token)
        expect(found_session).to eq(session)
        expect(found_session.user).to eq(user)

        # Extend session
        original_expiry = session.expires_at
        session.extend_expiry!
        expect(session.expires_at).to be > original_expiry

        # Revoke session
        session.revoke!
        expect(session.active?).to be false
        expect(Session.find_by_token(session.session_token)).to be_nil
      end
    end

    describe "email verification workflow" do
      it "handles email verification process" do
        unverified_user = create(:user, :unverified)
        expect(unverified_user.email_verified?).to be false

        # Generate verification token
        token = unverified_user.generate_email_verification_token
        expect(token).to be_present
        expect(unverified_user.email_verification_token).to eq(token)

        # Verify token
        found_user = User.find_by_email_verification_token(token)
        expect(found_user).to eq(unverified_user)

        # Complete verification
        found_user.verify_email!
        expect(found_user.email_verified?).to be true
        expect(found_user.email_verified_at).to be_present
      end
    end
  end
end
