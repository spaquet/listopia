# spec/helpers/comments_helper_spec.rb
require 'rails_helper'

RSpec.describe CommentsHelper, type: :helper do
  describe "#comment_delete_path" do
    let(:user) { create(:user) }

    context "when comment is on a List" do
      let(:list) { create(:list, owner: user) }
      let(:comment) { create(:comment, commentable: list, user: user) }

      it "returns the correct delete path for list comment" do
        expected_path = list_comment_path(list, comment)
        expect(helper.comment_delete_path(comment)).to eq(expected_path)
      end

      it "uses the list as the first resource parameter" do
        result = helper.comment_delete_path(comment)
        # Path should contain list ID
        expect(result).to include(list.id.to_s)
        expect(result).to include(comment.id.to_s)
      end

      it "generates valid path string" do
        result = helper.comment_delete_path(comment)
        expect(result).to be_a(String)
        expect(result).to match(%r{/lists/.+/comments/.+})
      end
    end

    context "when comment is on a ListItem" do
      let(:list) { create(:list, owner: user) }
      let(:list_item) { create(:list_item, list: list) }
      let(:comment) { create(:comment, commentable: list_item, user: user) }

      it "returns the correct delete path for list item comment" do
        expected_path = list_list_item_comment_path(list, list_item, comment)
        expect(helper.comment_delete_path(comment)).to eq(expected_path)
      end

      it "uses the list and list_item as resource parameters" do
        result = helper.comment_delete_path(comment)
        # Path should contain both list and list_item IDs
        expect(result).to include(list.id.to_s)
        expect(result).to include(list_item.id.to_s)
        expect(result).to include(comment.id.to_s)
      end

      it "generates valid nested path string" do
        result = helper.comment_delete_path(comment)
        expect(result).to be_a(String)
        # Route uses /items/ not /list_items/
        expect(result).to match(%r{/lists/.+/items/.+/comments/.+})
      end

      it "correctly traverses to parent list through list_item" do
        result = helper.comment_delete_path(comment)
        # Verify the path structure: /lists/:list_id/list_items/:list_item_id/comments/:comment_id
        parts = result.split('/')
        list_index = parts.find_index(list.id.to_s)
        list_item_index = parts.find_index(list_item.id.to_s)

        expect(list_index).to be < list_item_index
      end
    end

    context "when comment is on an unknown commentable type" do
      let(:comment) { create(:comment, user: user) }

      before do
        # Manually set commentable_type to something invalid
        comment.update_column(:commentable_type, "InvalidType")
      end

      it "raises an error" do
        expect {
          helper.comment_delete_path(comment)
        }.to raise_error("Unknown commentable type: InvalidType")
      end

      it "includes the invalid type in the error message" do
        begin
          helper.comment_delete_path(comment)
        rescue => e
          expect(e.message).to include("InvalidType")
        end
      end
    end

    context "with multiple comments on same resource" do
      let(:list) { create(:list, owner: user) }
      let(:comment1) { create(:comment, commentable: list, user: user) }
      let(:comment2) { create(:comment, commentable: list, user: user) }

      it "generates unique paths for each comment" do
        path1 = helper.comment_delete_path(comment1)
        path2 = helper.comment_delete_path(comment2)

        expect(path1).not_to eq(path2)
        expect(path1).to include(comment1.id.to_s)
        expect(path2).to include(comment2.id.to_s)
      end

      it "uses the same list ID in both paths" do
        path1 = helper.comment_delete_path(comment1)
        path2 = helper.comment_delete_path(comment2)

        expect(path1).to include(list.id.to_s)
        expect(path2).to include(list.id.to_s)
      end
    end

    context "edge cases" do
      let(:list) { create(:list, owner: user) }
      let(:comment) { create(:comment, commentable: list, user: user) }

      it "works with UUID primary keys" do
        result = helper.comment_delete_path(comment)
        # Both IDs should be present and be valid UUIDs
        expect(result).to include(list.id.to_s)
        expect(result).to include(comment.id.to_s)
      end

      it "generates HTTP DELETE compatible path" do
        result = helper.comment_delete_path(comment)
        # Path should not include HTTP method in URL
        expect(result).not_to include("_method")
        expect(result).to be_a(String)
      end
    end
  end
end
