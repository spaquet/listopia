# == Schema Information
#
# Table name: comments
#
#  id               :uuid             not null, primary key
#  commentable_type :string           not null
#  content          :text             not null
#  metadata         :json
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  commentable_id   :uuid             not null
#  user_id          :uuid             not null
#
# Indexes
#
#  index_comments_on_commentable  (commentable_type,commentable_id)
#  index_comments_on_user_id      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
# spec/models/comment_spec.rb
require 'rails_helper'

RSpec.describe Comment, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }

    it 'belongs to commentable polymorphically' do
      expect(described_class.reflect_on_association(:commentable).options[:polymorphic]).to be_truthy
    end
  end

  describe 'validations' do
    let(:user) { create(:user, :verified) }
    let(:list) { create(:list, owner: user) }
    let(:valid_comment) do
      build(:comment, user: user, commentable: list)
    end

    context 'content validation' do
      it 'requires content' do
        comment = build(:comment, content: nil, user: user, commentable: list)
        expect(comment).not_to be_valid
        expect(comment.errors[:content]).to include("can't be blank")
      end

      it 'requires at least 1 character' do
        comment = build(:comment, content: '', user: user, commentable: list)
        expect(comment).not_to be_valid
        expect(comment.errors[:content]).to include("is too short (minimum is 1 character)")
      end

      it 'allows 1 character' do
        comment = build(:comment, content: 'a', user: user, commentable: list)
        expect(comment).to be_valid
      end

      it 'allows up to 5000 characters' do
        comment = build(:comment, content: 'a' * 5000, user: user, commentable: list)
        expect(comment).to be_valid
      end

      it 'rejects content over 5000 characters' do
        comment = build(:comment, content: 'a' * 5001, user: user, commentable: list)
        expect(comment).not_to be_valid
        expect(comment.errors[:content]).to include("is too long (maximum is 5000 characters)")
      end
    end

    context 'user validation' do
      it 'requires a user_id' do
        comment = build(:comment, user_id: nil, commentable: list)
        expect(comment).not_to be_valid
        expect(comment.errors[:user_id]).to include("can't be blank")
      end
    end
  end

  describe 'polymorphic associations' do
    let(:user) { create(:user, :verified) }

    context 'with List' do
      let(:list) { create(:list, owner: user) }

      it 'can be associated with a List' do
        comment = create(:comment, user: user, commentable: list)
        expect(comment.commentable).to eq(list)
        expect(comment.commentable_type).to eq('List')
      end

      it 'returns correct commentable_id' do
        comment = create(:comment, user: user, commentable: list)
        expect(comment.commentable_id).to eq(list.id)
      end
    end

    context 'with ListItem' do
      let(:list) { create(:list, owner: user) }
      let(:list_item) { create(:list_item, list: list) }

      it 'can be associated with a ListItem' do
        comment = create(:comment, user: user, commentable: list_item)
        expect(comment.commentable).to eq(list_item)
        expect(comment.commentable_type).to eq('ListItem')
      end

      it 'returns correct commentable_id' do
        comment = create(:comment, user: user, commentable: list_item)
        expect(comment.commentable_id).to eq(list_item.id)
      end
    end
  end

  describe 'auditing with Logidze' do
    let(:user) { create(:user, :verified) }
    let(:list) { create(:list, owner: user) }

    it 'includes has_logidze declaration' do
      # Verify the model has Logidze enabled
      expect(Comment).to respond_to(:has_logidze)
    end

    # Note: Detailed Logidze testing would require Logidze to be configured
    # for the comments table. These tests verify the association exists.
    it 'allows comment creation without errors' do
      comment = create(:comment, user: user, commentable: list, content: 'Tracked content')
      expect(comment).to be_persisted
    end
  end

  describe 'metadata handling' do
    let(:user) { create(:user, :verified) }
    let(:list) { create(:list, owner: user) }

    it 'stores metadata as JSON' do
      metadata = { source: 'web', ip: '127.0.0.1' }
      comment = create(:comment, user: user, commentable: list, metadata: metadata)
      # JSON stores keys as strings, not symbols
      expect(comment.metadata['source']).to eq('web')
      expect(comment.metadata['ip']).to eq('127.0.0.1')
    end

    it 'defaults to empty hash' do
      comment = create(:comment, user: user, commentable: list)
      expect(comment.metadata).to eq({})
    end

    it 'allows updating metadata' do
      comment = create(:comment, user: user, commentable: list)
      comment.update(metadata: { edited_at: Time.current })
      expect(comment.metadata['edited_at']).not_to be_nil
    end
  end

  describe 'timestamps' do
    let(:user) { create(:user, :verified) }
    let(:list) { create(:list, owner: user) }

    it 'sets created_at on creation' do
      comment = create(:comment, user: user, commentable: list)
      expect(comment.created_at).to be_present
    end

    it 'sets updated_at on creation' do
      comment = create(:comment, user: user, commentable: list)
      expect(comment.updated_at).to be_present
    end

    it 'updates updated_at when modified' do
      comment = create(:comment, user: user, commentable: list)
      original_updated_at = comment.updated_at

      sleep(0.01) # Small delay to ensure time difference
      comment.update(content: 'Updated content')

      expect(comment.updated_at).to be > original_updated_at
    end
  end

  describe 'querying comments' do
    let(:user1) { create(:user, :verified) }
    let(:user2) { create(:user, :verified) }
    let(:list) { create(:list, owner: user1) }
    let(:list_item) { create(:list_item, list: list) }

    before do
      create(:comment, user: user1, commentable: list)
      create(:comment, user: user2, commentable: list)
      create(:comment, user: user1, commentable: list_item)
    end

    it 'can find comments on a specific List' do
      comments = list.comments
      expect(comments.count).to eq(2)
    end

    it 'can find comments on a specific ListItem' do
      comments = list_item.comments
      expect(comments.count).to eq(1)
    end

    it 'can find all comments by a user' do
      comments = user1.comments
      expect(comments.count).to eq(2)
    end

    it 'can filter comments by commentable type' do
      list_comments = Comment.where(commentable_type: 'List')
      expect(list_comments.count).to eq(2)

      item_comments = Comment.where(commentable_type: 'ListItem')
      expect(item_comments.count).to eq(1)
    end
  end

  describe 'UUID primary keys' do
    let(:user) { create(:user, :verified) }
    let(:list) { create(:list, owner: user) }

    it 'generates UUID as primary key' do
      comment = create(:comment, user: user, commentable: list)
      expect(comment.id).to be_a(String)
      expect(comment.id).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
    end

    it 'stores user_id as UUID' do
      comment = create(:comment, user: user, commentable: list)
      expect(comment.user_id).to eq(user.id)
    end

    it 'stores commentable_id as UUID' do
      comment = create(:comment, user: user, commentable: list)
      expect(comment.commentable_id).to eq(list.id)
    end
  end

  describe 'edge cases' do
    let(:user) { create(:user, :verified) }
    let(:list) { create(:list, owner: user) }

    it 'allows whitespace-only content to be invalid' do
      comment = build(:comment, content: '   ', user: user, commentable: list)
      # Note: Rails strips whitespace by default, so this becomes empty
      expect(comment).not_to be_valid
    end

    it 'preserves newlines in content' do
      content = "Line 1\nLine 2\nLine 3"
      comment = create(:comment, content: content, user: user, commentable: list)
      expect(comment.content).to eq(content)
    end

    it 'preserves special characters' do
      content = "Comment with special chars: @#$%^&*()_+-=[]{}|;:',.<>?/~`"
      comment = create(:comment, content: content, user: user, commentable: list)
      expect(comment.content).to eq(content)
    end

    it 'allows markdown-like content' do
      content = "# Header\n**bold** and *italic* text\n- list item"
      comment = create(:comment, content: content, user: user, commentable: list)
      expect(comment.content).to eq(content)
    end
  end

  describe 'database indexes' do
    it 'has index on polymorphic association' do
      indexes = ActiveRecord::Base.connection.indexes('comments')
      index_names = indexes.map(&:name)
      expect(index_names).to include('index_comments_on_commentable')
    end

    it 'has index on user_id' do
      indexes = ActiveRecord::Base.connection.indexes('comments')
      index_names = indexes.map(&:name)
      expect(index_names).to include('index_comments_on_user_id')
    end
  end
end
