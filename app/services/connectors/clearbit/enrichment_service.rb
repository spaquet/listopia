module Connectors
  module Clearbit
    class EnrichmentService < ApplicationService
      CLEARBIT_URL = "https://person.clearbit.com/v2/combined/find"

      def initialize(email:)
        @email = email
      end

      def call
        api_key = ENV["CLEARBIT_API_KEY"]
        return failure(errors: ["Clearbit API key not configured"]) if api_key.blank?

        uri = URI("#{CLEARBIT_URL}?email=#{ERB::Util.url_encode(@email)}")
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Bearer #{api_key}"

        resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }

        case resp.code.to_i
        when 200
          data = JSON.parse(resp.body)
          success(data: data["person"] || data)
        when 202
          # Clearbit is looking up asynchronously — retry later
          failure(errors: ["Clearbit lookup pending"])
        when 404
          failure(errors: ["No Clearbit data found for #{@email}"])
        else
          failure(errors: ["Clearbit error: #{resp.code}"])
        end
      rescue StandardError => e
        failure(errors: ["Clearbit enrichment error: #{e.message}"])
      end
    end
  end
end
