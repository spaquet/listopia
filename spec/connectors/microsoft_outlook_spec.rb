require "rails_helper"

RSpec.describe Connectors::MicrosoftOutlook, type: :model do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, creator: user) }
  let(:account) { create(:connectors_account, :with_tokens, provider: "microsoft_outlook", user: user, organization: organization) }

  before do
    Current.user = user
    Current.organization = organization
  end

  after { Current.reset }

  let(:connector) { described_class.new(account) }

  describe "metadata" do
    it "has correct class-level attributes" do
      expect(described_class.key).to eq("microsoft_outlook")
      expect(described_class.name).to eq("Microsoft Outlook Calendar")
      expect(described_class.category).to eq("calendars")
      expect(described_class.oauth_required?).to be true
    end

    it "includes Outlook OAuth scopes" do
      scopes = described_class.oauth_scopes_list
      expect(scopes).to include("Calendars.Read")
      expect(scopes).to include("Calendars.ReadWrite")
      expect(scopes).to include("offline_access")
    end

    it "defines settings schema" do
      schema = described_class.schema
      expect(schema).to have_key(:default_calendar_id)
      expect(schema).to have_key(:sync_direction)
      expect(schema).to have_key(:auto_sync)
    end
  end

  describe "#test_connection" do
    it "tests connection by fetching calendars" do
      allow_any_instance_of(Connectors::Microsoft::CalendarFetchService).to receive(:fetch_calendars).and_return([
        { "id" => "primary", "name" => "Primary Calendar" }
      ])

      result = connector.test_connection

      expect(result[:status]).to eq("connected")
      expect(result[:calendars_count]).to eq(1)
    end
  end

  describe "#pull" do
    it "pulls events from Outlook" do
      allow_any_instance_of(Connectors::Microsoft::EventSyncService).to receive(:pull_events).and_return(
        count: 3,
        events: []
      )

      result = connector.pull

      expect(result[:status]).to eq("success")
      expect(result[:records_pulled]).to eq(3)
    end
  end

  describe "#push" do
    it "pushes items to Outlook" do
      allow_any_instance_of(Connectors::Microsoft::EventSyncService).to receive(:push_events).and_return(
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
      expect(Connectors::Registry.find("microsoft_outlook")).to eq(described_class)
    end

    it "appears in calendars category" do
      expect(Connectors::Registry.by_category("calendars")).to include(described_class)
    end
  end
end
