# spec/helpers/dashboard_helper_spec.rb
require 'rails_helper'

RSpec.describe DashboardHelper, type: :helper do
  describe "#adaptive_dashboard_mode_title" do
    it "returns 'What's Next?' for recommendations mode" do
      expect(helper.adaptive_dashboard_mode_title(:recommendations)).to eq("What's Next?")
    end

    it "returns 'List Focus' for spotlight mode" do
      expect(helper.adaptive_dashboard_mode_title(:spotlight)).to eq("List Focus")
    end

    it "returns 'Ready to Act' for action mode" do
      expect(helper.adaptive_dashboard_mode_title(:action)).to eq("Ready to Act")
    end

    it "returns 'Let's Get Going' for nudge mode" do
      expect(helper.adaptive_dashboard_mode_title(:nudge)).to eq("Let's Get Going")
    end

    it "returns 'Dashboard' for unknown mode" do
      expect(helper.adaptive_dashboard_mode_title(:unknown)).to eq("Dashboard")
    end

    it "returns 'Dashboard' for nil mode" do
      expect(helper.adaptive_dashboard_mode_title(nil)).to eq("Dashboard")
    end
  end

  describe "#adaptive_dashboard_mode_subtitle" do
    it "returns correct subtitle for recommendations" do
      result = helper.adaptive_dashboard_mode_subtitle(:recommendations)
      expect(result).to eq("Smart recommendations based on your activity")
    end

    it "returns correct subtitle for spotlight" do
      result = helper.adaptive_dashboard_mode_subtitle(:spotlight)
      expect(result).to eq("Deep dive into this list")
    end

    it "returns correct subtitle for action" do
      result = helper.adaptive_dashboard_mode_subtitle(:action)
      expect(result).to eq("Suggested actions you can take right now")
    end

    it "returns correct subtitle for nudge" do
      result = helper.adaptive_dashboard_mode_subtitle(:nudge)
      expect(result).to eq("Time to get back on track")
    end

    it "returns default subtitle for unknown mode" do
      result = helper.adaptive_dashboard_mode_subtitle(:unknown)
      expect(result).to eq("Your personalized dashboard")
    end

    it "returns default subtitle for nil" do
      result = helper.adaptive_dashboard_mode_subtitle(nil)
      expect(result).to eq("Your personalized dashboard")
    end
  end

  describe "#mode_badge_class" do
    it "returns blue classes for recommendations" do
      result = helper.mode_badge_class(:recommendations)
      expect(result).to eq("bg-blue-100 text-blue-800")
    end

    it "returns purple classes for spotlight" do
      result = helper.mode_badge_class(:spotlight)
      expect(result).to eq("bg-purple-100 text-purple-800")
    end

    it "returns green classes for action" do
      result = helper.mode_badge_class(:action)
      expect(result).to eq("bg-green-100 text-green-800")
    end

    it "returns orange classes for nudge" do
      result = helper.mode_badge_class(:nudge)
      expect(result).to eq("bg-orange-100 text-orange-800")
    end

    it "returns gray classes for unknown mode" do
      result = helper.mode_badge_class(:unknown)
      expect(result).to eq("bg-gray-100 text-gray-800")
    end

    it "returns gray classes for nil" do
      result = helper.mode_badge_class(nil)
      expect(result).to eq("bg-gray-100 text-gray-800")
    end
  end

  describe "#recommendation_gradient" do
    it "returns red gradient for scores 100 and above" do
      result = helper.recommendation_gradient(100)
      expect(result).to include("from-red-50")
      expect(result).to include("to-orange-50")
      expect(result).to include("border-l-4")
      expect(result).to include("border-red-500")
    end

    it "returns red gradient for scores above 100" do
      result = helper.recommendation_gradient(150)
      expect(result).to include("from-red-50")
    end

    it "returns yellow gradient for scores 50-100" do
      result = helper.recommendation_gradient(75)
      expect(result).to include("from-yellow-50")
      expect(result).to include("to-amber-50")
      expect(result).to include("border-yellow-500")
    end

    it "returns yellow gradient for score exactly 50" do
      result = helper.recommendation_gradient(50)
      expect(result).to include("from-yellow-50")
    end

    it "returns blue gradient for scores 25-50" do
      result = helper.recommendation_gradient(35)
      expect(result).to include("from-blue-50")
      expect(result).to include("to-indigo-50")
      expect(result).to include("border-blue-500")
    end

    it "returns blue gradient for score exactly 25" do
      result = helper.recommendation_gradient(25)
      expect(result).to include("from-blue-50")
    end

    it "returns gray gradient for scores below 25" do
      result = helper.recommendation_gradient(10)
      expect(result).to include("from-gray-50")
      expect(result).to include("to-gray-100")
    end

    it "returns gray gradient for score 0" do
      result = helper.recommendation_gradient(0)
      expect(result).to include("from-gray-50")
    end
  end

  describe "#time_ago_in_words_or_date" do
    it "returns empty string for nil date" do
      expect(helper.time_ago_in_words_or_date(nil)).to eq("")
    end

    it "returns 'Today' for current date" do
      result = helper.time_ago_in_words_or_date(Time.current)
      expect(result).to eq("Today")
    end

    it "returns 'Yesterday' for 1 day ago" do
      result = helper.time_ago_in_words_or_date(1.day.ago)
      expect(result).to eq("Yesterday")
    end

    it "returns days count for 2-6 days ago" do
      result = helper.time_ago_in_words_or_date(3.days.ago)
      expect(result).to eq("3 days ago")
    end

    it "returns weeks count for 7-30 days ago" do
      result = helper.time_ago_in_words_or_date(14.days.ago)
      expect(result).to eq("2 weeks ago")
    end

    it "returns formatted date for more than 30 days ago" do
      date = 60.days.ago
      result = helper.time_ago_in_words_or_date(date)
      expect(result).to match(/[A-Z][a-z]{2}\s+\d{2},\s+\d{4}/)
    end

    it "handles exactly 1 day boundary" do
      result = helper.time_ago_in_words_or_date(1.day.ago)
      expect(result).to eq("Yesterday")
    end

    it "handles exactly 7 days boundary" do
      result = helper.time_ago_in_words_or_date(7.days.ago)
      expect(result).to include("weeks")
    end

    it "handles exactly 30 days boundary" do
      result = helper.time_ago_in_words_or_date(30.days.ago)
      expect(result).to include("weeks")
    end
  end

  describe "#time_until_words" do
    it "returns empty string for nil date" do
      expect(helper.time_until_words(nil)).to eq("")
    end

    it "returns 'Today' for today" do
      result = helper.time_until_words(Date.current)
      expect(result).to eq("Today")
    end

    it "returns 'Tomorrow' for 1 day from now" do
      result = helper.time_until_words(Date.current + 1.day)
      expect(result).to eq("Tomorrow")
    end

    it "returns days count for 2-6 days away" do
      result = helper.time_until_words(Date.current + 3.days)
      expect(result).to eq("In 3 days")
    end

    it "returns weeks count for 7-30 days away" do
      result = helper.time_until_words(Date.current + 14.days)
      expect(result).to eq("In 2 weeks")
    end

    it "returns formatted date for more than 30 days away" do
      date = Date.current + 60.days
      result = helper.time_until_words(date)
      expect(result).to match(/[A-Z][a-z]{2}\s+\d{2},\s+\d{4}/)
    end

    it "handles exactly 1 day away boundary" do
      result = helper.time_until_words(Date.current + 1.day)
      expect(result).to eq("Tomorrow")
    end

    it "handles exactly 7 days away boundary" do
      result = helper.time_until_words(Date.current + 7.days)
      expect(result).to include("weeks")
    end

    it "handles exactly 30 days away boundary" do
      result = helper.time_until_words(Date.current + 30.days)
      expect(result).to include("weeks")
    end

    it "handles past dates gracefully" do
      result = helper.time_until_words(Date.current - 5.days)
      expect(result).to match(/[A-Z][a-z]{2}\s+\d{2},\s+\d{4}/)
    end
  end
end
