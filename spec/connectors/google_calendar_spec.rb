require "rails_helper"

RSpec.describe Connectors::GoogleCalendar, type: :model do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, creator: user) }
  let(:account) { create(:connectors_account, :with_tokens, provider: "google_calendar", user: user, organization: organization) }

  before do
    Current.user = user
    Current.organization = organization
  end

  after { Current.reset }

  let(:connector) { described_class.new(account) }

  describe "metadata" do
    it "has correct class-level attributes" do
      expect(described_class.key).to eq("google_calendar")
      expect(described_class.name).to eq("Google Calendar")
      expect(described_class.category).to eq("calendars")
      expect(described_class.oauth_required?).to be true
    end

    it "includes Google Calendar OAuth scopes" do
      scopes = described_class.oauth_scopes_list
      expect(scopes).to include("https://www.googleapis.com/auth/calendar")
      expect(scopes).to include("https://www.googleapis.com/auth/calendar.events")
    end

    it "defines settings schema with calendar selection" do
      schema = described_class.schema
      expect(schema).to have_key(:default_calendar_id)
      expect(schema).to have_key(:sync_direction)
      expect(schema).to have_key(:auto_sync)
    end
  end

  describe "#test_connection" do
    it "tests connection by fetching calendars" do
      allow_any_instance_of(Connectors::Google::CalendarFetchService).to receive(:fetch_calendars).and_return([
        { "id" => "primary", "summary" => "Primary Calendar" }
      ])

      result = connector.test_connection

      expect(result[:status]).to eq("connected")
      expect(result[:calendars_count]).to eq(1)
    end
  end

  describe "#pull" do
    it "pulls events from Google Calendar" do
      allow_any_instance_of(Connectors::Google::EventSyncService).to receive(:pull_events).and_return(
        count: 5,
        events: [
          { "id" => "event1", "summary" => "Meeting 1" },
          { "id" => "event2", "summary" => "Meeting 2" }
        ]
      )

      result = connector.pull

      expect(result[:status]).to eq("success")
      expect(result[:records_pulled]).to eq(5)
    end
  end

  describe "#push" do
    it "pushes items to Google Calendar" do
      allow_any_instance_of(Connectors::Google::EventSyncService).to receive(:push_events).and_return(
        count: 2,
        events: []
      )

      data = [
        { id: "1", title: "Task 1" },
        { id: "2", title: "Task 2" }
      ]

      result = connector.push(data)

      expect(result[:status]).to eq("success")
      expect(result[:records_pushed]).to eq(2)
    end
  end

  describe "registry integration" do
    it "is registered in the connector registry" do
      expect(Connectors::Registry.find("google_calendar")).to eq(described_class)
    end

    it "appears in calendars category" do
      expect(Connectors::Registry.by_category("calendars")).to include(described_class)
    end
  end
end
