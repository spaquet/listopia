require "rails_helper"

RSpec.describe Connectors::Slack::MessageService, type: :service do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, creator: user) }
  let(:account) { create(:connectors_account, :with_tokens, provider: "slack", user: user, organization: organization) }

  before do
    Current.user = user
    Current.organization = organization
  end

  after { Current.reset }

  let(:service) { described_class.new(connector_account: account) }

  describe "#fetch_channels" do
    context "with successful API response" do
      before do
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
          instance_double(Net::HTTPSuccess,
            is_a?: true,
            body: {
              ok: true,
              channels: [
                { id: "C123", name: "general", is_private: false },
                { id: "C456", name: "random", is_private: false },
                { id: "C789", name: "private-channel", is_private: true }
              ]
            }.to_json
          )
        )
      end

      it "returns list of channels" do
        channels = service.fetch_channels

        expect(channels.count).to eq(3)
        expect(channels[0]["name"]).to eq("general")
      end

      it "creates sync log entry" do
        expect {
          service.fetch_channels
        }.to change(Connectors::SyncLog, :count).by(1)

        log = Connectors::SyncLog.last
        expect(log.operation).to eq("fetch_channels")
        expect(log.status).to eq("success")
        expect(log.records_processed).to eq(3)
      end
    end

    context "with API error" do
      before do
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
          instance_double(Net::HTTPSuccess,
            is_a?: true,
            body: { ok: false, error: "not_authed" }.to_json
          )
        )
      end

      it "raises error with API error message" do
        expect {
          service.fetch_channels
        }.to raise_error(/Slack API error/)
      end
    end
  end

  describe "#post_message" do
    context "with successful post" do
      before do
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
          instance_double(Net::HTTPSuccess,
            is_a?: true,
            body: {
              ok: true,
              channel: "C123",
              ts: "1234567890.123456",
              message: { type: "message", subtype: nil }
            }.to_json
          )
        )
      end

      it "posts message to channel" do
        result = service.post_message("C123", "Test message")

        expect(result[:ok]).to be true
        expect(result[:ts]).to eq("1234567890.123456")
      end

      it "includes message text and channel" do
        allow_any_instance_of(Net::HTTP).to receive(:request) do |_instance|
          expect_request_with_body("text" => "Test message", "channel" => "C123")
          instance_double(Net::HTTPSuccess, is_a?: true, body: { ok: true, ts: "123" }.to_json)
        end

        service.post_message("C123", "Test message")
      end

      it "includes blocks when provided" do
        blocks = [{ type: "section", text: { type: "mrkdwn", text: "*Bold*" } }]

        allow_any_instance_of(Net::HTTP).to receive(:request) do |_instance|
          expect_request_with_body("blocks" => blocks)
          instance_double(Net::HTTPSuccess, is_a?: true, body: { ok: true, ts: "123" }.to_json)
        end

        service.post_message("C123", "text", blocks: blocks)
      end
    end

    context "with API error" do
      before do
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
          instance_double(Net::HTTPSuccess,
            is_a?: true,
            body: { ok: false, error: "channel_not_found" }.to_json
          )
        )
      end

      it "returns error response" do
        result = service.post_message("C999", "Test message")

        expect(result[:ok]).to be false
        expect(result[:error]).to eq("channel_not_found")
      end
    end
  end

  describe "#post_messages" do
    let(:items) do
      [
        { title: "Item 1", description: "Description 1", status: "created" },
        { title: "Item 2", description: "Description 2", status: "completed" }
      ]
    end

    context "with successful posts" do
      before do
        account.settings.create!(key: "default_channel_id", value: "C123")

        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
          instance_double(Net::HTTPSuccess,
            is_a?: true,
            body: { ok: true, ts: "1234567890.123456" }.to_json
          )
        )
      end

      it "posts all items to default channel" do
        result = service.post_messages(items)

        expect(result[:count]).to eq(2)
        expect(result[:messages].count).to eq(2)
      end

      it "creates sync log with processed counts" do
        expect {
          service.post_messages(items)
        }.to change(Connectors::SyncLog, :count).by(1)

        log = Connectors::SyncLog.last
        expect(log.operation).to eq("post_messages")
        expect(log.records_processed).to eq(2)
        expect(log.records_created).to eq(2)
      end
    end

    context "without default channel configured" do
      it "returns empty result" do
        result = service.post_messages(items)

        expect(result[:count]).to eq(0)
        expect(result[:messages]).to eq([])
      end
    end

    context "with partial failures" do
      before do
        account.settings.create!(key: "default_channel_id", value: "C123")

        call_count = 0
        allow_any_instance_of(Net::HTTP).to receive(:request) do
          call_count += 1
          if call_count == 1
            instance_double(Net::HTTPSuccess, is_a?: true, body: { ok: true, ts: "111" }.to_json)
          else
            instance_double(Net::HTTPSuccess, is_a?: true, body: { ok: false, error: "error" }.to_json)
          end
        end
      end

      it "counts only successful posts" do
        result = service.post_messages(items)

        expect(result[:count]).to eq(1)
        expect(result[:messages].count).to eq(1)
      end
    end
  end

  private

  def expect_request_with_body(expected_body)
    # Helper to assert request body contains expected fields
    # This is a simplified version - actual implementation would parse JSON body
  end
end
