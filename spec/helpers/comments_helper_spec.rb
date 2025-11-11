require 'rails_helper'

RSpec.describe CommentsHelper, type: :helper do
  let(:list) { create(:list) }
  let(:list_item) { create(:list_item, list: list) }

  describe '#comment_delete_path' do
    it 'generates correct path for a comment on a List' do
      comment = create(:comment, commentable: list)
      path = helper.comment_delete_path(comment)
      expect(path).to include("/lists/#{list.id}/comments/#{comment.id}")
    end

    it 'generates correct path for a comment on a ListItem' do
      comment = create(:comment, commentable: list_item)
      path = helper.comment_delete_path(comment)
      expect(path).to include("/lists/#{list.id}/items/#{list_item.id}/comments/#{comment.id}")
    end

    it 'raises error for unsupported commentable type' do
      comment = create(:comment)
      allow(comment).to receive(:commentable_type).and_return("UnsupportedType")

      expect {
        helper.comment_delete_path(comment)
      }.to raise_error(RuntimeError, /Unknown commentable type/)
    end
  end
end
