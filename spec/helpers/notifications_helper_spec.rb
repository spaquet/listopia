# spec/helpers/notifications_helper_spec.rb
require 'rails_helper'

RSpec.describe NotificationsHelper, type: :helper do
  describe "#notification_color" do
    it "returns blue for collaboration notification" do
      notification = double(notification_type: "collaboration")
      expect(helper.notification_color(notification)).to eq("blue")
    end

    it "returns green for completed list_status" do
      notification = double(notification_type: "list_status", new_status: "completed")
      expect(helper.notification_color(notification)).to eq("green")
    end

    it "returns yellow for archived list_status" do
      notification = double(notification_type: "list_status", new_status: "archived")
      expect(helper.notification_color(notification)).to eq("yellow")
    end

    it "returns blue for active list_status" do
      notification = double(notification_type: "list_status", new_status: "active")
      expect(helper.notification_color(notification)).to eq("blue")
    end

    it "returns gray for unknown list_status" do
      notification = double(notification_type: "list_status", new_status: "unknown")
      expect(helper.notification_color(notification)).to eq("gray")
    end

    it "returns green for created item_activity" do
      notification = double(notification_type: "item_activity", action_type: "created")
      expect(helper.notification_color(notification)).to eq("green")
    end

    it "returns emerald for completed item_activity" do
      notification = double(notification_type: "item_activity", action_type: "completed")
      expect(helper.notification_color(notification)).to eq("emerald")
    end

    it "returns red for deleted item_activity" do
      notification = double(notification_type: "item_activity", action_type: "deleted")
      expect(helper.notification_color(notification)).to eq("red")
    end

    it "returns blue for updated item_activity" do
      notification = double(notification_type: "item_activity", action_type: "updated")
      expect(helper.notification_color(notification)).to eq("blue")
    end

    it "returns gray for unknown item_activity action" do
      notification = double(notification_type: "item_activity", action_type: "unknown")
      expect(helper.notification_color(notification)).to eq("gray")
    end

    it "returns gray for unknown notification type" do
      notification = double(notification_type: "unknown_type")
      expect(helper.notification_color(notification)).to eq("gray")
    end
  end

  describe "#notification_type_badge" do
    it "returns collaboration badge" do
      notification = double(notification_type: "collaboration")
      result = helper.notification_type_badge(notification)
      expect(result).to include("Collaboration")
      expect(result).to include("bg-blue-100")
      expect(result).to include("text-blue-800")
    end

    it "returns list_status badge" do
      notification = double(notification_type: "list_status")
      result = helper.notification_type_badge(notification)
      expect(result).to include("List Status")
      expect(result).to include("bg-purple-100")
      expect(result).to include("text-purple-800")
    end

    it "returns item_activity badge" do
      notification = double(notification_type: "item_activity")
      result = helper.notification_type_badge(notification)
      expect(result).to include("Item Activity")
      expect(result).to include("bg-green-100")
      expect(result).to include("text-green-800")
    end

    it "returns default badge for unknown type" do
      notification = double(notification_type: "unknown_type")
      result = helper.notification_type_badge(notification)
      expect(result).to include("Notification")
      expect(result).to include("bg-gray-100")
      expect(result).to include("text-gray-800")
    end

    it "wraps content in span tag" do
      notification = double(notification_type: "collaboration")
      result = helper.notification_type_badge(notification)
      expect(result).to start_with("<span")
      expect(result).to end_with("</span>")
    end

    it "includes badge styling classes" do
      notification = double(notification_type: "collaboration")
      result = helper.notification_type_badge(notification)
      expect(result).to include("inline-flex")
      expect(result).to include("rounded-full")
      expect(result).to include("text-xs")
      expect(result).to include("font-medium")
    end
  end

  describe "#notification_time" do
    it "returns relative time for recent notifications" do
      notification = double(created_at: 2.hours.ago)
      result = helper.notification_time(notification)
      expect(result).to include("ago")
    end

    it "returns absolute time for old notifications" do
      notification = double(created_at: 3.days.ago)
      result = helper.notification_time(notification)
      expect(result).to match(/[A-Z][a-z]{2}\s+\d{2},\s+\d{4}/)
    end

    it "includes AM/PM for old notifications" do
      notification = double(created_at: 5.days.ago)
      result = helper.notification_time(notification)
      expect(result).to match(/(AM|PM)/)
    end

    it "handles current time" do
      notification = double(created_at: Time.current)
      result = helper.notification_time(notification)
      expect(result).to include("ago")
    end

    it "handles exactly 1 day ago" do
      notification = double(created_at: 1.day.ago)
      result = helper.notification_time(notification)
      expect(result).to match(/(AM|PM)/)
    end

    it "handles 23 hours ago with relative time" do
      notification = double(created_at: 23.hours.ago)
      result = helper.notification_time(notification)
      expect(result).to include("ago")
    end
  end

  describe "#notification_summary" do
    let(:user) { create(:user) }

    it "returns hash with required keys" do
      result = helper.notification_summary(user)
      expect(result).to be_a(Hash)
      expect(result).to have_key(:total)
      expect(result).to have_key(:unread)
      expect(result).to have_key(:unseen)
      expect(result).to have_key(:today)
    end

    it "returns 0 for all counts when no notifications" do
      result = helper.notification_summary(user)
      expect(result[:total]).to eq(0)
      expect(result[:unread]).to eq(0)
      expect(result[:unseen]).to eq(0)
      expect(result[:today]).to eq(0)
    end

    it "counts total notifications for user" do
      # Using Noticed gem's notification model
      expect(user.notifications).to receive(:count).and_return(5)
      result = helper.notification_summary(user)
      expect(result[:total]).to eq(5)
    end

    it "counts unread notifications" do
      expect(user.notifications).to receive(:unread).and_return(double(count: 3))
      result = helper.notification_summary(user)
      expect(result[:unread]).to eq(3)
    end

    it "counts unseen notifications" do
      expect(user.notifications).to receive(:unseen).and_return(double(count: 2))
      result = helper.notification_summary(user)
      expect(result[:unseen]).to eq(2)
    end

    it "counts today's notifications" do
      expect(user.notifications).to receive(:where).with(created_at: Date.current.all_day).and_return(double(count: 1))
      result = helper.notification_summary(user)
      expect(result[:today]).to eq(1)
    end
  end
end
