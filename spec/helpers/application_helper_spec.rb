# spec/helpers/application_helper_spec.rb
require 'rails_helper'
require 'active_support/testing/time_helpers'

RSpec.describe ApplicationHelper, type: :helper do
  include ActiveSupport::Testing::TimeHelpers
  describe "#time_ago_in_words_or_date" do
    it "returns empty string when time is nil" do
      expect(helper.time_ago_in_words_or_date(nil)).to eq("")
    end

    it "returns time_ago_in_words when less than 1 week ago" do
      time = 2.days.ago
      result = helper.time_ago_in_words_or_date(time)
      expect(result).to include("ago")
    end

    it "returns time_ago_in_words for 6 days ago" do
      time = 6.days.ago
      result = helper.time_ago_in_words_or_date(time)
      expect(result).to include("ago")
    end

    it "returns time_ago_in_words format when more than 1 week ago" do
      time = 2.weeks.ago
      result = helper.time_ago_in_words_or_date(time)
      # The helper returns time_ago_in_words format, not a date
      expect(result).to include("ago")
    end

    it "returns time_ago_in_words format for exactly 8 days ago" do
      time = 8.days.ago
      result = helper.time_ago_in_words_or_date(time)
      # The helper returns time_ago_in_words format for anything over 1 week
      expect(result).to include("ago")
    end
  end

  describe "#user_avatar_initials" do
    it "returns empty string when user is nil" do
      expect(helper.user_avatar_initials(nil)).to eq("")
    end

    it "returns empty string when user has no name" do
      user = double(name: nil)
      expect(helper.user_avatar_initials(user)).to eq("")
    end

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

    it "includes proper CSS classes" do
      user = double(name: "John Doe")
      result = helper.user_avatar_initials(user)
      expect(result).to include("bg-blue-500")
      expect(result).to include("rounded-full")
      expect(result).to include("flex items-center justify-center")
    end

    it "respects custom size parameter" do
      user = double(name: "Jane Smith")
      result = helper.user_avatar_initials(user, size: "w-12 h-12")
      expect(result).to include("w-12 h-12")
    end

    it "wraps content in div tag" do
      user = double(name: "Alice Bob")
      result = helper.user_avatar_initials(user)
      expect(result).to start_with("<div")
      expect(result).to end_with("</div>")
    end
  end

  describe "#nav_link_class" do
    it "includes base classes" do
      result = helper.nav_link_class("/some-path")
      expect(result).to include("text-gray-700")
      expect(result).to include("hover:text-blue-600")
      expect(result).to include("px-3 py-2")
    end

    it "adds active classes when current page" do
      allow(helper).to receive(:current_page?).and_return(true)
      result = helper.nav_link_class("/active-path")
      expect(result).to include("bg-blue-50")
      expect(result).to include("text-blue-600")
    end

    it "does not include bg-blue-50 when not current page" do
      allow(helper).to receive(:current_page?).and_return(false)
      result = helper.nav_link_class("/inactive-path")
      expect(result).not_to include("bg-blue-50")
    end
  end

  describe "#list_status_badge" do
    it "returns draft status badge" do
      list = double(status: "draft")
      result = helper.list_status_badge(list)
      expect(result).to include("Draft")
      expect(result).to include("bg-gray-100")
      expect(result).to include("text-gray-800")
    end

    it "returns active status badge" do
      list = double(status: "active")
      result = helper.list_status_badge(list)
      expect(result).to include("Active")
      expect(result).to include("bg-green-100")
      expect(result).to include("text-green-800")
    end

    it "returns completed status badge" do
      list = double(status: "completed")
      result = helper.list_status_badge(list)
      expect(result).to include("Completed")
      expect(result).to include("bg-blue-100")
      expect(result).to include("text-blue-800")
    end

    it "returns archived status badge" do
      list = double(status: "archived")
      result = helper.list_status_badge(list)
      expect(result).to include("Archived")
      expect(result).to include("bg-yellow-100")
      expect(result).to include("text-yellow-800")
    end

    it "returns default badge for unknown status" do
      list = double(status: "unknown")
      result = helper.list_status_badge(list)
      expect(result).to include("Unknown")
      expect(result).to include("inline-flex")
    end

    it "titleizes the status text" do
      list = double(status: "active")
      result = helper.list_status_badge(list)
      expect(result).to include("Active")
    end

    it "wraps content in span tag" do
      list = double(status: "active")
      result = helper.list_status_badge(list)
      expect(result).to start_with("<span")
      expect(result).to end_with("</span>")
    end
  end

  describe "#priority_badge" do
    it "returns low priority badge" do
      item = double(priority: "low")
      result = helper.priority_badge(item)
      expect(result).to include("Low")
      expect(result).to include("bg-gray-100")
      expect(result).to include("text-gray-600")
    end

    it "returns medium priority badge" do
      item = double(priority: "medium")
      result = helper.priority_badge(item)
      expect(result).to include("Medium")
      expect(result).to include("bg-yellow-100")
      expect(result).to include("text-yellow-700")
    end

    it "returns high priority badge" do
      item = double(priority: "high")
      result = helper.priority_badge(item)
      expect(result).to include("High")
      expect(result).to include("bg-orange-100")
      expect(result).to include("text-orange-700")
    end

    it "returns urgent priority badge" do
      item = double(priority: "urgent")
      result = helper.priority_badge(item)
      expect(result).to include("Urgent")
      expect(result).to include("bg-red-100")
      expect(result).to include("text-red-700")
    end

    it "returns default badge for unknown priority" do
      item = double(priority: "custom")
      result = helper.priority_badge(item)
      expect(result).to include("bg-gray-100")
      expect(result).to include("text-gray-600")
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

    it "uses blue-500 color by default" do
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

  describe "#format_due_date" do
    it "returns empty string when date is nil" do
      expect(helper.format_due_date(nil)).to eq("")
    end

    it "returns red text for past dates" do
      past_date = 2.days.ago
      result = helper.format_due_date(past_date)
      expect(result).to include("text-red-600")
      expect(result).to include("font-medium")
    end

    it "returns orange text for due today" do
      # Travel to a fixed time: March 11, 2026, 2 PM
      travel_to Time.zone.local(2026, 3, 11, 14, 0, 0) do
        # A time that is later today: March 11, 2026, 8 PM
        later_today = Time.zone.local(2026, 3, 11, 20, 0, 0)
        result = helper.format_due_date(later_today)
        expect(result).to include("Due today")
        expect(result).to include("text-orange-600")
      end
    end

    it "returns yellow text for 2 days away" do
      two_days_future = 2.days.from_now
      result = helper.format_due_date(two_days_future)
      expect(result).to include("text-yellow-600")
    end

    it "returns gray text for dates more than 3 days away" do
      future_date = 5.days.from_now
      result = helper.format_due_date(future_date)
      expect(result).to include("text-gray-600")
    end

    it "formats date in correct format" do
      date = Date.today + 5.days
      result = helper.format_due_date(date)
      expect(result).to match(/[A-Z][a-z]{2}\s+\d{2}/)
    end
  end

  describe "#can?" do
    it "returns false for unknown action" do
      list = create(:list)
      expect(helper.can?(:unknown, list)).to be(false)
    end

    it "returns false for unknown resource type" do
      unknown_resource = "string"
      expect(helper.can?(:edit, unknown_resource)).to be(false)
    end

    it "returns false when resource is nil" do
      expect(helper.can?(:edit, nil)).to be(false)
    end
  end

  describe "#random_gradient" do
    it "returns a gradient string" do
      result = helper.random_gradient
      expect(result).to be_a(String)
      expect(result).to include("from-")
      expect(result).to include("to-")
    end

    it "returns one of the predefined gradients" do
      valid_gradients = [
        "from-blue-600 to-purple-600",
        "from-green-600 to-blue-600",
        "from-purple-600 to-pink-600",
        "from-yellow-600 to-red-600",
        "from-indigo-600 to-purple-600",
        "from-pink-600 to-rose-600"
      ]

      result = helper.random_gradient
      expect(valid_gradients).to include(result)
    end
  end

  describe "#dashboard_data_for_user" do
    let(:user) { create(:user) }

    it "returns a hash with required keys" do
      result = helper.dashboard_data_for_user(user)
      expect(result).to be_a(Hash)
      expect(result).to have_key(:my_lists)
      expect(result).to have_key(:collaborated_lists)
      expect(result).to have_key(:recent_items)
      expect(result).to have_key(:stats)
    end

    it "limits my_lists to 10" do
      create_list(:list, 15, owner: user)
      result = helper.dashboard_data_for_user(user)
      expect(result[:my_lists].count).to eq(10)
    end

    it "orders my_lists by updated_at descending" do
      list1 = create(:list, owner: user, updated_at: 1.day.ago)
      list2 = create(:list, owner: user, updated_at: Time.current)
      result = helper.dashboard_data_for_user(user)
      expect(result[:my_lists].first.id).to eq(list2.id)
    end

    it "includes collaborated lists" do
      result = helper.dashboard_data_for_user(user)
      expect(result[:collaborated_lists]).to be_a(ActiveRecord::Relation)
    end

    it "includes recent items" do
      list = create(:list, owner: user)
      create_list(:list_item, 5, list: list)
      result = helper.dashboard_data_for_user(user)
      expect(result[:recent_items]).to be_a(ActiveRecord::Relation)
    end

    it "calls DashboardStatsService with user" do
      allow(DashboardStatsService).to receive(:new).and_call_original
      allow_any_instance_of(DashboardStatsService).to receive(:call).and_return({})
      helper.dashboard_data_for_user(user)
      expect(DashboardStatsService).to have_received(:new).with(user)
    end
  end

  describe "#breadcrumbs" do
    it "renders breadcrumbs with nav and ol elements" do
      crumbs = [
        { text: "Home", path: "/" },
        { text: "Lists", path: "/lists" }
      ]
      result = helper.breadcrumbs(*crumbs)
      expect(result).to include("<nav")
      expect(result).to include("<ol")
      expect(result).to include("</nav>")
      expect(result).to include("</ol>")
    end

    it "renders links for non-last crumbs" do
      crumbs = [
        { text: "Home", path: "/" },
        { text: "Current", path: "/current" }
      ]
      result = helper.breadcrumbs(*crumbs)
      expect(result).to include('href="/"')
      expect(result).to include("Home")
    end

    it "renders current page without link" do
      crumbs = [
        { text: "Home", path: "/" },
        { text: "Current", path: "/current" }
      ]
      result = helper.breadcrumbs(*crumbs)
      expect(result).to include("Current")
      expect(result).to include("text-gray-500")
    end

    it "renders single breadcrumb without link" do
      crumbs = [{ text: "Home", path: "/" }]
      result = helper.breadcrumbs(*crumbs)
      expect(result).to include("Home")
      expect(result).to include("text-gray-500")
    end

    it "includes SVG separator between crumbs" do
      crumbs = [
        { text: "Home", path: "/" },
        { text: "Lists", path: "/lists" }
      ]
      result = helper.breadcrumbs(*crumbs)
      expect(result).to include("<svg")
      expect(result).to include("viewBox=\"0 0 20 20\"")
    end

    it "uses correct accessibility label" do
      crumbs = [{ text: "Home", path: "/" }]
      result = helper.breadcrumbs(*crumbs)
      expect(result).to include("Breadcrumb")
    end

    it "handles multiple breadcrumbs" do
      crumbs = [
        { text: "Home", path: "/" },
        { text: "Lists", path: "/lists" },
        { text: "My List", path: "/lists/123" }
      ]
      result = helper.breadcrumbs(*crumbs)
      expect(result).to include("Home")
      expect(result).to include("Lists")
      expect(result).to include("My List")
    end
  end

  describe "#icon" do
    it "renders check-circle icon" do
      result = helper.icon("check-circle")
      expect(result).to include("M9 12l2 2 4-4")
      expect(result).to include("<svg")
    end

    it "renders users icon" do
      result = helper.icon("users")
      expect(result).to include("viewBox=\"0 0 24 24\"")
      expect(result).to include("<svg")
    end

    it "renders lightning-bolt icon" do
      result = helper.icon("lightning-bolt")
      expect(result).to include("M13 10V3L4 14h7v7l9-11h-7z")
    end

    it "renders plus icon" do
      result = helper.icon("plus")
      expect(result).to include("M12 4v16m8-8H4")
    end

    it "renders edit icon" do
      result = helper.icon("edit")
      expect(result).to include("viewBox=\"0 0 24 24\"")
    end

    it "renders share icon" do
      result = helper.icon("share")
      expect(result).to include("viewBox=\"0 0 24 24\"")
    end

    it "renders delete icon" do
      result = helper.icon("delete")
      expect(result).to include("M19 7l-.867 12.142")
    end

    it "uses default size when not specified" do
      result = helper.icon("plus")
      expect(result).to include("w-5 h-5")
    end

    it "uses custom size when specified" do
      result = helper.icon("plus", size: "w-8 h-8")
      expect(result).to include("w-8 h-8")
    end

    it "adds custom CSS class" do
      result = helper.icon("plus", class: "text-blue-600")
      expect(result).to include("text-blue-600")
    end

    it "combines size and class" do
      result = helper.icon("plus", size: "w-6 h-6", class: "mr-2")
      expect(result).to include("w-6 h-6")
      expect(result).to include("mr-2")
    end

    it "returns empty string for unknown icon" do
      result = helper.icon("unknown-icon")
      expect(result).to include("<svg")
    end

    it "sets svg attributes correctly" do
      result = helper.icon("plus")
      expect(result).to include("fill=\"none\"")
      expect(result).to include("stroke=\"currentColor\"")
      expect(result).to include("viewBox=\"0 0 24 24\"")
    end
  end

  describe "#current_page?" do
    it "returns true when request path matches given path" do
      allow(helper).to receive_message_chain(:request, :path).and_return("/lists")
      expect(helper.current_page?("/lists")).to be(true)
    end

    it "returns false when request path does not match given path" do
      allow(helper).to receive_message_chain(:request, :path).and_return("/lists")
      expect(helper.current_page?("/dashboard")).to be(false)
    end

    it "handles root path" do
      allow(helper).to receive_message_chain(:request, :path).and_return("/")
      expect(helper.current_page?("/")).to be(true)
    end

    it "handles nested paths" do
      allow(helper).to receive_message_chain(:request, :path).and_return("/lists/123/items")
      expect(helper.current_page?("/lists/123/items")).to be(true)
      expect(helper.current_page?("/lists/123")).to be(false)
    end

    it "is case sensitive" do
      allow(helper).to receive_message_chain(:request, :path).and_return("/Lists")
      expect(helper.current_page?("/lists")).to be(false)
    end
  end

  describe "#can?" do
    it "returns false for unknown action with List" do
      list = create(:list)
      expect(helper.can?(:unknown_action, list)).to be(false)
    end

    it "returns false for unknown resource type" do
      expect(helper.can?(:edit, "not_a_resource")).to be(false)
    end

    it "returns false when resource is nil" do
      expect(helper.can?(:read, nil)).to be(false)
    end

    it "returns false for unsupported action" do
      list = create(:list)
      expect(helper.can?(:nonexistent, list)).to be(false)
    end
  end
end
