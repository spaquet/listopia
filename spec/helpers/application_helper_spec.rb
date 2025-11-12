# spec/helpers/application_helper_spec.rb
require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
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
      today = Time.current.end_of_day - 1.hour
      result = helper.format_due_date(today)
      expect(result).to include("Due today")
      expect(result).to include("text-orange-600")
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
end
