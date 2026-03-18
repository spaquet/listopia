module Connectors
  module Messaging
    module Slack
      # Post messages to Slack channels
      class MessageService < Connectors::BaseService
        SLACK_API_URL = "https://slack.com/api"

      # Fetch list of channels in the workspace
      def fetch_channels
        with_sync_log(operation: "fetch_channels") do |log|
          ensure_fresh_token!

          channels = fetch_from_slack("conversations.list",
            types: "public_channel,private_channel",
            limit: 100
          )

          log.update!(records_processed: channels.count)

          channels
        end
      end

      # Post a message to a channel
      def post_message(channel_id, text, blocks: nil)
        with_sync_log(operation: "post_message") do |log|
          ensure_fresh_token!

          payload = {
            channel: channel_id,
            text: text
          }

          payload[:blocks] = blocks if blocks.present?

          result = post_to_slack("chat.postMessage", payload)

          log.update!(records_processed: 1, records_created: result[:success] ? 1 : 0)

          result
        end
      end

      # Post multiple messages (e.g., list of completed items)
      def post_messages(items)
        with_sync_log(operation: "post_messages") do |log|
          ensure_fresh_token!

          channel_id = connector_account.settings.find_by(key: "default_channel_id")&.value
          return { count: 0, messages: [] } unless channel_id

          messages = []
          created = 0

          items.each do |item|
            message_text = build_message_text(item)
            blocks = build_message_blocks(item)

            result = post_to_slack("chat.postMessage",
              channel: channel_id,
              text: message_text,
              blocks: blocks
            )

            if result[:ok]
              created += 1
              messages << { id: result[:ts], text: message_text }
            end
          end

          log.update!(
            records_processed: items.count,
            records_created: created
          )

          { count: created, messages: messages }
        end
      end

      private

      def fetch_from_slack(endpoint, **params)
        response = make_slack_request(:get, endpoint, params)
        data = JSON.parse(response.body)

        raise "Slack API error: #{data["error"]}" unless data["ok"]

        data["channels"] || data["conversations"] || []
      end

      def post_to_slack(endpoint, payload)
        response = make_slack_request(:post, endpoint, payload)
        JSON.parse(response.body)
      end

      def make_slack_request(method, endpoint, params_or_payload)
        require "net/http"
        require "uri"
        require "json"

        url = "#{SLACK_API_URL}/#{endpoint}"
        uri = URI(url)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = if method == :post
          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/json"
          request.body = params_or_payload.to_json
          request
        else
          uri.query = URI.encode_www_form(params_or_payload)
          Net::HTTP::Get.new(uri)
        end

        request["Authorization"] = "Bearer #{connector_account.access_token}"

        response = http.request(request)

        raise "Slack API error: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        response
      end

      # Build message text for a list item
      def build_message_text(item)
        title = item[:title] || "Untitled"
        status = item[:status] || "created"

        "✅ *#{title}*\nStatus: #{status}"
      end

      # Build rich message blocks for a list item
      def build_message_blocks(item)
        [
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "*#{item[:title] || 'Untitled'}*\n#{item[:description] || 'No description'}"
            }
          },
          {
            type: "context",
            elements: [
              {
                type: "mrkdwn",
                text: "📋 From Listopia"
              }
            ]
          }
        ]
      end
    end
  end
end
