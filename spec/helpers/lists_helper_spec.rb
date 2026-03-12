# spec/helpers/lists_helper_spec.rb
require 'rails_helper'

RSpec.describe ListsHelper, type: :helper do
  describe "#list_completion_stats" do
    it "returns correct stats when list is empty" do
      list = create(:list)
      stats = helper.list_completion_stats(list)
      expect(stats).to eq({
        total: 0,
        completed: 0,
        pending: 0,
        percentage: 0
      })
    end

    it "returns correct stats when all items are completed" do
      list = create(:list)
      create_list(:list_item, 5, list: list, status: 2)
      stats = helper.list_completion_stats(list)
      expect(stats).to eq({
        total: 5,
        completed: 5,
        pending: 0,
        percentage: 100
      })
    end

    it "returns correct stats when no items are completed" do
      list = create(:list)
      create_list(:list_item, 5, list: list, status: 0)
      stats = helper.list_completion_stats(list)
      expect(stats).to eq({
        total: 5,
        completed: 0,
        pending: 5,
        percentage: 0
      })
    end

    it "returns correct stats for partially completed list" do
      list = create(:list)
      create_list(:list_item, 3, list: list, status: 2)
      create_list(:list_item, 2, list: list, status: 0)
      stats = helper.list_completion_stats(list)
      expect(stats).to eq({
        total: 5,
        completed: 3,
        pending: 2,
        percentage: 60
      })
    end

    it "rounds percentage correctly" do
      list = create(:list)
      create_list(:list_item, 1, list: list, status: 2)
      create_list(:list_item, 2, list: list, status: 0)
      stats = helper.list_completion_stats(list)
      expect(stats[:percentage]).to eq(33)
    end
  end

  describe "#list_type_badge" do
    it "displays personal list with correct styling" do
      list = double(list_type: "personal")
      result = helper.list_type_badge(list)
      expect(result).to include("Personal")
      expect(result).to include("bg-green-100")
      expect(result).to include("text-green-800")
    end

    it "displays professional list with correct styling" do
      list = double(list_type: "professional")
      result = helper.list_type_badge(list)
      expect(result).to include("Professional")
      expect(result).to include("bg-blue-100")
      expect(result).to include("text-blue-800")
    end

    it "wraps content in span tag" do
      list = double(list_type: "personal")
      result = helper.list_type_badge(list)
      expect(result).to start_with("<span")
      expect(result).to end_with("</span>")
    end
  end

  describe "#list_status_badge" do
    it "displays draft status with correct styling" do
      list = double(status: "draft")
      result = helper.list_status_badge(list)
      expect(result).to include("Draft")
      expect(result).to include("bg-gray-100")
      expect(result).to include("text-gray-800")
    end

    it "displays active status with correct styling" do
      list = double(status: "active")
      result = helper.list_status_badge(list)
      expect(result).to include("Active")
      expect(result).to include("bg-green-100")
      expect(result).to include("text-green-800")
    end

    it "displays completed status with correct styling" do
      list = double(status: "completed")
      result = helper.list_status_badge(list)
      expect(result).to include("Completed")
      expect(result).to include("bg-blue-100")
      expect(result).to include("text-blue-800")
    end

    it "displays archived status with correct styling" do
      list = double(status: "archived")
      result = helper.list_status_badge(list)
      expect(result).to include("Archived")
      expect(result).to include("bg-yellow-100")
      expect(result).to include("text-yellow-800")
    end

    it "wraps content in span tag" do
      list = double(status: "active")
      result = helper.list_status_badge(list)
      expect(result).to start_with("<span")
      expect(result).to end_with("</span>")
    end
  end

  describe "#list_sharing_status" do
    it "displays 'Public' for public lists" do
      list = double(is_public?: true, collaborators: double(any?: false))
      result = helper.list_sharing_status(list)
      expect(result).to include("Public")
      expect(result).to include("bg-green-100")
    end

    it "displays 'Shared' with count for lists with collaborators" do
      list = double(
        is_public?: false,
        collaborators: double(any?: true, count: 3)
      )
      result = helper.list_sharing_status(list)
      expect(result).to include("Shared (3)")
      expect(result).to include("bg-purple-100")
    end

    it "displays 'Private' for non-public lists without collaborators" do
      list = double(
        is_public?: false,
        collaborators: double(any?: false)
      )
      result = helper.list_sharing_status(list)
      expect(result).to include("Private")
      expect(result).to include("bg-gray-100")
    end
  end

  describe "#list_owner_badge" do
    it "displays 'you' when given user is owner" do
      user = create(:user)
      list = create(:list, owner: user)
      result = helper.list_owner_badge(list, user)
      expect(result).to include("Owned by you")
    end

    it "displays owner name when given user is not owner" do
      owner = create(:user, name: "Jane Doe")
      list = create(:list, owner: owner)
      other_user = create(:user)
      result = helper.list_owner_badge(list, other_user)
      expect(result).to include("Owned by Jane Doe")
    end

    it "displays owner information correctly" do
      # The User model requires name presence, so all users have names
      # The presence check in the helper is defensive programming
      owner = create(:user, name: "Test Owner")
      list = create(:list, owner: owner)
      other_user = create(:user)
      result = helper.list_owner_badge(list, other_user)
      expect(result).to include("Test Owner")
    end
  end

  describe "#list_permission_for_user" do
    it "returns :none when user is nil" do
      list = create(:list)
      expect(helper.list_permission_for_user(list, nil)).to eq(:none)
    end

    it "returns :owner when user is list owner" do
      user = create(:user)
      list = create(:list, owner: user)
      expect(helper.list_permission_for_user(list, user)).to eq(:owner)
    end

    it "returns :public_read for public list when user is not owner" do
      owner = create(:user)
      user = create(:user)
      list = create(:list, owner: owner, is_public: true)
      allow(list).to receive(:respond_to?).and_return(false)
      expect(helper.list_permission_for_user(list, user)).to eq(:public_read)
    end

    it "returns collaborator permission for shared list" do
      owner = create(:user)
      user = create(:user)
      list = create(:list, owner: owner)
      create(:collaborator, collaboratable: list, user: user, permission: "write")
      expect(helper.list_permission_for_user(list, user)).to eq(:write)
    end

    it "returns :none when user is not owner, not public, and not collaborator" do
      owner = create(:user)
      user = create(:user)
      list = create(:list, owner: owner, is_public: false)
      allow(list).to receive(:respond_to?).and_return(false)
      expect(helper.list_permission_for_user(list, user)).to eq(:none)
    end
  end

  describe "#can_edit_list?" do
    it "returns true for list owner" do
      user = create(:user)
      list = create(:list, owner: user)
      expect(helper.can_edit_list?(list, user)).to be(true)
    end

    it "returns true for write permission collaborator" do
      owner = create(:user)
      user = create(:user)
      list = create(:list, owner: owner)
      create(:collaborator, collaboratable: list, user: user, permission: "write")
      expect(helper.can_edit_list?(list, user)).to be(true)
    end

    it "returns false for read-only collaborator" do
      owner = create(:user)
      user = create(:user)
      list = create(:list, owner: owner)
      create(:collaborator, collaboratable: list, user: user, permission: "read")
      expect(helper.can_edit_list?(list, user)).to be(false)
    end

    it "returns false for non-owner non-collaborator" do
      owner = create(:user)
      user = create(:user)
      list = create(:list, owner: owner)
      expect(helper.can_edit_list?(list, user)).to be(false)
    end
  end

  describe "#can_share_list?" do
    it "returns true for list owner" do
      user = create(:user)
      list = create(:list, owner: user)
      expect(helper.can_share_list?(list, user)).to be(true)
    end

    it "returns true for write permission collaborator" do
      owner = create(:user)
      user = create(:user)
      list = create(:list, owner: owner)
      create(:collaborator, collaboratable: list, user: user, permission: "write")
      expect(helper.can_share_list?(list, user)).to be(true)
    end

    it "returns false for read-only collaborator" do
      owner = create(:user)
      user = create(:user)
      list = create(:list, owner: owner)
      create(:collaborator, collaboratable: list, user: user, permission: "read")
      expect(helper.can_share_list?(list, user)).to be(false)
    end

    it "returns false for non-owner non-collaborator" do
      owner = create(:user)
      user = create(:user)
      list = create(:list, owner: owner)
      expect(helper.can_share_list?(list, user)).to be(false)
    end
  end

  describe "#can_delete_list?" do
    it "returns true only for list owner" do
      user = create(:user)
      list = create(:list, owner: user)
      expect(helper.can_delete_list?(list, user)).to be(true)
    end

    it "returns false for non-owner" do
      owner = create(:user)
      user = create(:user)
      list = create(:list, owner: owner)
      expect(helper.can_delete_list?(list, user)).to be(false)
    end

    it "returns false even for write permission collaborator" do
      owner = create(:user)
      user = create(:user)
      list = create(:list, owner: owner)
      create(:collaborator, collaboratable: list, user: user, permission: "write")
      expect(helper.can_delete_list?(list, user)).to be(false)
    end
  end

  describe "#can_view_list?" do
    it "returns true for owner" do
      user = create(:user)
      list = create(:list, owner: user)
      expect(helper.can_view_list?(list, user)).to be(true)
    end

    it "returns true for collaborator with read permission" do
      owner = create(:user)
      user = create(:user)
      list = create(:list, owner: owner)
      create(:collaborator, collaboratable: list, user: user, permission: "read")
      expect(helper.can_view_list?(list, user)).to be(true)
    end

    it "returns true for collaborator with write permission" do
      owner = create(:user)
      user = create(:user)
      list = create(:list, owner: owner)
      create(:collaborator, collaboratable: list, user: user, permission: "write")
      expect(helper.can_view_list?(list, user)).to be(true)
    end

    it "returns false for non-owner non-collaborator" do
      owner = create(:user)
      user = create(:user)
      list = create(:list, owner: owner)
      expect(helper.can_view_list?(list, user)).to be(false)
    end
  end

  describe "#available_list_actions" do
    it "returns edit action when user can edit" do
      user = create(:user)
      list = create(:list, owner: user)
      actions = helper.available_list_actions(list, user)
      expect(actions).to include(:edit)
    end

    it "returns share action when user can share" do
      user = create(:user)
      list = create(:list, owner: user)
      actions = helper.available_list_actions(list, user)
      expect(actions).to include(:share)
    end

    it "returns delete action when user can delete" do
      user = create(:user)
      list = create(:list, owner: user)
      actions = helper.available_list_actions(list, user)
      expect(actions).to include(:delete)
    end

    it "includes duplicate for viewers" do
      owner = create(:user)
      user = create(:user)
      list = create(:list, owner: owner)
      create(:collaborator, collaboratable: list, user: user, permission: "read")
      actions = helper.available_list_actions(list, user)
      expect(actions).to include(:duplicate)
    end

    it "returns all actions for owner" do
      user = create(:user)
      list = create(:list, owner: user)
      actions = helper.available_list_actions(list, user)
      expect(actions).to include(:edit, :share, :duplicate, :delete)
    end

    it "returns empty array for non-owner non-collaborator" do
      owner = create(:user)
      user = create(:user)
      list = create(:list, owner: owner)
      actions = helper.available_list_actions(list, user)
      expect(actions).to be_empty
    end
  end

  describe "#can_access_list?" do
    it "checks view permission when permission is :read" do
      user = create(:user)
      list = create(:list, owner: user)
      expect(helper.can_access_list?(list, user, :read)).to be(true)
    end

    it "checks edit permission when permission is :edit" do
      user = create(:user)
      list = create(:list, owner: user)
      expect(helper.can_access_list?(list, user, :edit)).to be(true)
    end

    it "defaults to view permission when not specified" do
      user = create(:user)
      list = create(:list, owner: user)
      expect(helper.can_access_list?(list, user)).to be(true)
    end

    it "returns false for non-accessible lists" do
      owner = create(:user)
      user = create(:user)
      list = create(:list, owner: owner)
      expect(helper.can_access_list?(list, user, :read)).to be(false)
    end
  end

  describe "#can_duplicate_list?" do
    it "returns true when user can view list" do
      user = create(:user)
      list = create(:list, owner: user)
      expect(helper.can_duplicate_list?(list, user)).to be(true)
    end

    it "returns false when user cannot view list" do
      owner = create(:user)
      user = create(:user)
      list = create(:list, owner: owner)
      expect(helper.can_duplicate_list?(list, user)).to be(false)
    end
  end

  describe "#list_type_icon" do
    it "returns professional emoji for professional type" do
      result = helper.list_type_icon("professional")
      expect(result).to include("💼")
    end

    it "returns personal emoji for personal type" do
      result = helper.list_type_icon("personal")
      expect(result).to include("🏠")
    end

    it "returns shared emoji for shared type" do
      result = helper.list_type_icon("shared")
      expect(result).to include("👥")
    end

    it "returns default emoji for unknown type" do
      result = helper.list_type_icon("unknown")
      expect(result).to include("📝")
    end

    it "wraps content in span tag" do
      result = helper.list_type_icon("personal")
      expect(result).to start_with("<span")
      expect(result).to end_with("</span>")
    end
  end

  describe "#sharing_permission_options" do
    it "returns array of permission options" do
      options = helper.sharing_permission_options
      expect(options).to be_a(Array)
      expect(options.length).to eq(2)
    end

    it "includes read only option" do
      options = helper.sharing_permission_options
      expect(options).to include(["Read Only", "read"])
    end

    it "includes read and write option" do
      options = helper.sharing_permission_options
      expect(options).to include(["Read & Write", "write"])
    end
  end

  describe "#list_has_collaborators?" do
    it "returns false when list has no collaborators" do
      list = create(:list)
      expect(helper.list_has_collaborators?(list)).to be(false)
    end

    it "returns true when list has collaborators" do
      list = create(:list)
      user = create(:user)
      list.collaborators.create!(user: user, permission: "read")
      expect(helper.list_has_collaborators?(list)).to be(true)
    end

    it "returns true when list has multiple collaborators" do
      list = create(:list)
      user1 = create(:user)
      user2 = create(:user)
      user3 = create(:user)
      list.collaborators.create!(user: user1, permission: "read")
      list.collaborators.create!(user: user2, permission: "write")
      list.collaborators.create!(user: user3, permission: "read")
      expect(helper.list_has_collaborators?(list)).to be(true)
    end
  end

  describe "#item_type_icon" do
    it "delegates to item_type_icon_svg" do
      expect(helper).to receive(:item_type_icon_svg).with("task", css_class: "w-4 h-4")
      helper.item_type_icon("task")
    end
  end

  describe "#progress_bar" do
    it "generates progress bar HTML" do
      result = helper.progress_bar(50)
      expect(result).to include("bg-gray-200")
      expect(result).to include("rounded-full")
    end

    it "sets correct width percentage" do
      result = helper.progress_bar(75)
      expect(result).to include("width: 75%")
    end

    it "uses blue-500 color" do
      result = helper.progress_bar(50)
      expect(result).to include("bg-blue-500")
    end

    it "handles 0 percent" do
      result = helper.progress_bar(0)
      expect(result).to include("width: 0%")
    end

    it "handles 100 percent" do
      result = helper.progress_bar(100)
      expect(result).to include("width: 100%")
    end
  end
end
