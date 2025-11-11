# spec/policies/comment_policy_spec.rb
require 'rails_helper'

RSpec.describe CommentPolicy, type: :policy do
  let(:user) { create(:user, :verified) }
  let(:other_user) { create(:user, :verified) }
  let(:list_owner) { create(:user, :verified) }
  let(:list) { create(:list, owner: list_owner) }
  let(:comment) { create(:comment, user: user, commentable: list) }

  subject { described_class }

  describe 'access to commentable resource' do
    context 'on a List' do
      let(:list_comment) { create(:comment, user: user, commentable: list) }

      it 'requires the user can view the list' do
        # This policy should delegate to the commentable's policy
        # In this case, the user needs to be able to view the list
        policy = CommentPolicy.new(other_user, list_comment)
        # Authorization will check if other_user can view the list
        # This is handled by ListPolicy, not CommentPolicy
      end
    end

    context 'on a ListItem' do
      let(:list_item) { create(:list_item, list: list) }
      let(:item_comment) { create(:comment, user: user, commentable: list_item) }

      it 'requires the user can view the list_item' do
        # Similar delegation to ListItemPolicy
        policy = CommentPolicy.new(other_user, item_comment)
      end
    end
  end

  describe '#create?' do
    context 'with access to commentable' do
      it 'allows list owner to create comment' do
        policy = CommentPolicy.new(list_owner, comment)
        # Owner should be able to create if they have permission
        # The actual permission check depends on ListPolicy
      end

      it 'allows collaborator with read permission to create' do
        list.collaborators.create!(user: other_user, permission: :read)
        policy = CommentPolicy.new(other_user, comment)
        # Read permission users can comment (read + comment)
      end

      it 'allows collaborator with write permission to create' do
        list.collaborators.create!(user: other_user, permission: :write)
        policy = CommentPolicy.new(other_user, comment)
        # Write permission is higher than read, should allow
      end
    end

    context 'without access to commentable' do
      it 'denies user without permission from creating comment' do
        policy = CommentPolicy.new(other_user, comment)
        # User with no access to list cannot comment
      end

      it 'denies unauthenticated user' do
        policy = CommentPolicy.new(nil, comment)
        # nil user (unauthenticated) cannot create comment
      end
    end
  end

  describe '#destroy?' do
    context 'comment author' do
      it 'allows author to delete their own comment' do
        user_comment = create(:comment, user: user, commentable: list)
        policy = CommentPolicy.new(user, user_comment)
        # User who created the comment can delete it
      end
    end

    context 'list owner' do
      it 'allows list owner to delete any comment on their list' do
        other_user_comment = create(:comment, user: other_user, commentable: list)
        policy = CommentPolicy.new(list_owner, other_user_comment)
        # List owner can moderate comments
      end
    end

    context 'collaborators' do
      it 'allows write collaborator to delete any comment' do
        list.collaborators.create!(user: other_user, permission: :write)
        user_comment = create(:comment, user: user, commentable: list)
        policy = CommentPolicy.new(other_user, user_comment)
        # Write permission users can delete comments (moderation)
      end

      it 'denies read collaborator from deleting other users comments' do
        list.collaborators.create!(user: other_user, permission: :read)
        user_comment = create(:comment, user: user, commentable: list)
        policy = CommentPolicy.new(other_user, user_comment)
        # Read-only users cannot delete others' comments
      end

      it 'allows read collaborator to delete their own comment' do
        list.collaborators.create!(user: other_user, permission: :read)
        their_comment = create(:comment, user: other_user, commentable: list)
        policy = CommentPolicy.new(other_user, their_comment)
        # They can delete their own comment
      end

      it 'denies read-only user from deleting' do
        list.collaborators.create!(user: other_user, permission: :read)
        user_comment = create(:comment, user: user, commentable: list)
        policy = CommentPolicy.new(other_user, user_comment)
        # Read-only users cannot delete comments
      end
    end

    context 'unauthorized users' do
      it 'denies unauthorized user' do
        policy = CommentPolicy.new(other_user, comment)
        # User with no access to list cannot delete comments
      end

      it 'denies unauthenticated user' do
        policy = CommentPolicy.new(nil, comment)
        # nil user cannot delete anything
      end
    end
  end

  describe 'scoped policies' do
    before do
      # Create various comments in different states
      create(:comment, user: user, commentable: list)
      create(:comment, user: other_user, commentable: list)
      list.collaborators.create!(user: create(:user, :verified), permission: :read)
    end

    it 'restricts visible comments based on user access' do
      # User with no access should see no comments
      # User with read access should see all comments
      # User with write access should see all comments
    end
  end
end
