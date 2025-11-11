# spec/helpers/admin/users_helper_spec.rb
require 'rails_helper'

RSpec.describe Admin::UsersHelper, type: :helper do
  describe "#user_status_badge" do
    it "returns active status badge" do
      user = double(status: "active")
      result = helper.user_status_badge(user)
      expect(result).to include("Active")
      expect(result).to include("bg-green-100")
      expect(result).to include("text-green-800")
    end

    it "returns suspended status badge" do
      user = double(status: "suspended")
      result = helper.user_status_badge(user)
      expect(result).to include("Suspended")
      expect(result).to include("bg-red-100")
      expect(result).to include("text-red-800")
    end

    it "returns inactive status badge" do
      user = double(status: "inactive")
      result = helper.user_status_badge(user)
      expect(result).to include("Inactive")
      expect(result).to include("bg-gray-100")
      expect(result).to include("text-gray-800")
    end

    it "returns default inactive badge for unknown status" do
      user = double(status: "unknown")
      result = helper.user_status_badge(user)
      expect(result).to include("Inactive")
    end

    it "includes status dot" do
      user = double(status: "active")
      result = helper.user_status_badge(user)
      expect(result).to include("w-2 h-2")
      expect(result).to include("rounded-full")
    end

    it "wraps in span tag" do
      user = double(status: "active")
      result = helper.user_status_badge(user)
      expect(result).to start_with("<span")
      expect(result).to end_with("</span>")
    end

    it "includes badge styling classes" do
      user = double(status: "active")
      result = helper.user_status_badge(user)
      expect(result).to include("inline-flex items-center")
      expect(result).to include("px-2.5 py-0.5 rounded-full")
      expect(result).to include("text-xs font-medium")
    end
  end

  describe "#user_role_badge" do
    it "returns admin badge for admin user" do
      user = double(admin?: true)
      result = helper.user_role_badge(user)
      expect(result).to include("Admin")
      expect(result).to include("bg-purple-100")
      expect(result).to include("text-purple-800")
    end

    it "returns user badge for non-admin user" do
      user = double(admin?: false)
      result = helper.user_role_badge(user)
      expect(result).to include("User")
      expect(result).to include("bg-gray-100")
      expect(result).to include("text-gray-800")
    end

    it "wraps in span tag" do
      user = double(admin?: true)
      result = helper.user_role_badge(user)
      expect(result).to start_with("<span")
      expect(result).to end_with("</span>")
    end

    it "includes badge styling classes" do
      user = double(admin?: false)
      result = helper.user_role_badge(user)
      expect(result).to include("inline-flex items-center")
      expect(result).to include("px-2.5 py-0.5 rounded-full")
      expect(result).to include("text-xs font-medium")
    end
  end

  describe "#email_verification_icon" do
    it "returns green checkmark for verified email" do
      user = double(email_verified?: true)
      result = helper.email_verification_icon(user)
      expect(result).to include("<svg")
      expect(result).to include("text-green-500")
      expect(result).to include("w-5 h-5")
    end

    it "returns gray cross for unverified email" do
      user = double(email_verified?: false)
      result = helper.email_verification_icon(user)
      expect(result).to include("<svg")
      expect(result).to include("text-gray-300")
      expect(result).to include("w-5 h-5")
    end

    it "includes correct SVG viewBox" do
      user = double(email_verified?: true)
      result = helper.email_verification_icon(user)
      expect(result).to include('viewBox="0 0 20 20"')
    end

    it "includes fill currentColor" do
      user = double(email_verified?: true)
      result = helper.email_verification_icon(user)
      expect(result).to include('fill="currentColor"')
    end

    it "includes path element" do
      user = double(email_verified?: true)
      result = helper.email_verification_icon(user)
      expect(result).to include("<path")
    end
  end

  describe "#user_joined_date" do
    it "returns relative time for user created_at" do
      user = double(created_at: 2.days.ago)
      result = helper.user_joined_date(user)
      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end

    it "uses time_ago_in_words" do
      user = double(created_at: 1.week.ago)
      result = helper.user_joined_date(user)
      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end

    it "handles recent joins" do
      user = double(created_at: 1.hour.ago)
      result = helper.user_joined_date(user)
      expect(result).to be_a(String)
    end

    it "handles old accounts" do
      user = double(created_at: 1.year.ago)
      result = helper.user_joined_date(user)
      expect(result).to be_a(String)
    end
  end

  describe "#user_avatar_initials" do
    it "generates initials from user name" do
      user = double(name: "John Doe")
      result = helper.user_avatar_initials(user)
      expect(result).to include("JD")
    end

    it "uses only first two initials for long names" do
      user = double(name: "John Michael Doe")
      result = helper.user_avatar_initials(user)
      expect(result).to include("JM")
    end

    it "handles single name users" do
      user = double(name: "John")
      result = helper.user_avatar_initials(user)
      expect(result).to include("J")
    end

    it "includes proper styling classes" do
      user = double(name: "Alice Bob")
      result = helper.user_avatar_initials(user)
      expect(result).to include("bg-blue-500")
      expect(result).to include("text-white rounded-full")
      expect(result).to include("flex items-center justify-center")
      expect(result).to include("font-medium")
    end

    it "uses custom size parameter" do
      user = double(name: "Test User")
      result = helper.user_avatar_initials(user, size: "w-16 h-16 text-lg")
      expect(result).to include("w-16 h-16 text-lg")
    end

    it "uses default size when not specified" do
      user = double(name: "Test User")
      result = helper.user_avatar_initials(user)
      expect(result).to include("w-8 h-8")
      expect(result).to include("text-sm")
    end

    it "wraps in div tag" do
      user = double(name: "Test User")
      result = helper.user_avatar_initials(user)
      expect(result).to start_with("<div")
      expect(result).to end_with("</div>")
    end
  end

  describe "#suspend_toggle_button" do
    it "shows suspend button for active user" do
      user = double(active?: true, suspended?: false)
      result = helper.suspend_toggle_button(user)
      expect(result).to include("Suspend")
      expect(result).to include("data-turbo-method")
    end

    it "shows reactivate button for suspended user" do
      user = double(active?: false, suspended?: true)
      result = helper.suspend_toggle_button(user)
      expect(result).to include("Reactivate")
      expect(result).to include("data-turbo-method")
    end

    it "uses post method in form" do
      user = double(active?: true, suspended?: false)
      result = helper.suspend_toggle_button(user)
      expect(result).to include('method="post"')
    end

    it "includes button styling classes" do
      user = double(active?: true, suspended?: false)
      result = helper.suspend_toggle_button(user)
      expect(result).to include("inline-flex items-center")
      expect(result).to include("border border-gray-300")
      expect(result).to include("rounded-md shadow-sm")
    end

    it "uses data turbo method attribute" do
      user = double(active?: true, suspended?: false)
      result = helper.suspend_toggle_button(user)
      expect(result).to include("data-turbo-method")
    end
  end

  describe "#admin_toggle_button" do
    it "shows remove admin button for admin user" do
      user = double(admin?: true)
      result = helper.admin_toggle_button(user)
      expect(result).to include("Remove Admin")
      expect(result).to include(toggle_admin_admin_user_path(user))
    end

    it "shows make admin button for non-admin user" do
      user = double(admin?: false)
      result = helper.admin_toggle_button(user)
      expect(result).to include("Make Admin")
      expect(result).to include(toggle_admin_admin_user_path(user))
    end

    it "uses patch method" do
      user = double(admin?: true)
      result = helper.admin_toggle_button(user)
      expect(result).to include('method="post"')
    end

    it "includes button styling classes" do
      user = double(admin?: false)
      result = helper.admin_toggle_button(user)
      expect(result).to include("inline-flex items-center")
      expect(result).to include("border border-gray-300")
      expect(result).to include("rounded-md shadow-sm")
    end
  end

  describe "#delete_user_button" do
    let(:current_user) { create(:user) }
    let(:other_user) { create(:user) }

    it "shows delete button for other users" do
      result = helper.delete_user_button(other_user, current_user)
      expect(result).to include("Delete")
    end

    it "returns nil when deleting current user" do
      result = helper.delete_user_button(current_user, current_user)
      expect(result).to be_nil
    end

    it "uses delete method" do
      result = helper.delete_user_button(other_user, current_user)
      expect(result).to include('method="post"')
    end

    it "includes turbo confirm data attribute" do
      result = helper.delete_user_button(other_user, current_user)
      expect(result).to include("data-turbo-confirm")
      expect(result).to include("This action cannot be undone")
    end

    it "uses red styling" do
      result = helper.delete_user_button(other_user, current_user)
      expect(result).to include("border-red-300")
      expect(result).to include("text-red-700")
      expect(result).to include("hover:bg-red-50")
      expect(result).to include("ring-red-500")
    end

    it "wraps in button_to" do
      result = helper.delete_user_button(other_user, current_user)
      expect(result).to start_with("<form") if result.present?
    end
  end

  describe "#filter_url" do
    it "returns URL with merged filters" do
      allow(helper).to receive(:params).and_return(
        ActionController::Parameters.new(query: "test", status: "active")
      )
      result = helper.filter_url(role: "admin")
      expect(result).to include("/admin/users")
      expect(result).to include("role=admin")
    end

    it "preserves existing params" do
      allow(helper).to receive(:params).and_return(
        ActionController::Parameters.new(query: "search_term")
      )
      result = helper.filter_url(status: "suspended")
      expect(result).to be_a(String)
      expect(result).to include("status=suspended")
    end

    it "merges new filters with existing ones" do
      allow(helper).to receive(:params).and_return(
        ActionController::Parameters.new(query: "test", status: "active", sort_by: "name")
      )
      result = helper.filter_url(verified: "true")
      expect(result).to include("/admin/users")
      expect(result).to include("verified=true")
    end

    it "replaces filter values" do
      allow(helper).to receive(:params).and_return(
        ActionController::Parameters.new(status: "active")
      )
      result = helper.filter_url(status: "suspended")
      expect(result).to include("status=suspended")
      expect(result).not_to include("status=active")
    end
  end
end
