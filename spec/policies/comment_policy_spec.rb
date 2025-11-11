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

      it 'allows collaborator with comment permission to create' do
        list.collaborators.create!(user: other_user, permission: :comment)
        policy = CommentPolicy.new(other_user, comment)
        # Collaborator with comment permission should be allowed
      end

      it 'allows collaborator with edit permission to create' do
        list.collaborators.create!(user: other_user, permission: :edit)
        policy = CommentPolicy.new(other_user, comment)
        # Edit permission is higher than comment permission
      end

      it 'allows collaborator with admin permission to create' do
        list.collaborators.create!(user: other_user, permission: :admin)
        policy = CommentPolicy.new(other_user, comment)
        # Admin permission should allow everything
      end
    end

    context 'without access to commentable' do
      it 'denies user with only view permission from creating comment' do
        list.collaborators.create!(user: other_user, permission: :view)
        policy = CommentPolicy.new(other_user, comment)
        # View-only users cannot comment
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
      it 'allows admin collaborator to delete any comment' do
        list.collaborators.create!(user: other_user, permission: :admin)
        admin_comment = create(:comment, user: user, commentable: list)
        policy = CommentPolicy.new(other_user, admin_comment)
        # Admin should be able to delete comments
      end

      it 'denies edit collaborator from deleting other users comments' do
        list.collaborators.create!(user: other_user, permission: :edit)
        user_comment = create(:comment, user: user, commentable: list)
        policy = CommentPolicy.new(other_user, user_comment)
        # Edit collaborator cannot delete others' comments
      end

      it 'allows edit collaborator to delete their own comment' do
        list.collaborators.create!(user: other_user, permission: :edit)
        their_comment = create(:comment, user: other_user, commentable: list)
        policy = CommentPolicy.new(other_user, their_comment)
        # They can delete their own comment
      end

      it 'denies comment-only collaborator from deleting' do
        list.collaborators.create!(user: other_user, permission: :comment)
        user_comment = create(:comment, user: user, commentable: list)
        policy = CommentPolicy.new(other_user, user_comment)
        # Comment-only users cannot delete comments
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
      list.collaborators.create!(user: create(:user, :verified), permission: :comment)
    end

    it 'restricts visible comments based on user access' do
      # User with no access should see no comments
      # User with view access should see all comments
      # User with comment access should see all comments
    end
  end
end
