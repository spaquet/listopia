module Connectors
  module Github
    class EnrichmentService < ApplicationService
      def initialize(email:)
        @email = email
      end

      def call
        # Search GitHub users by email (only works if user made email public)
        search_url = "https://api.github.com/search/users?q=#{ERB::Util.url_encode(@email)}+in:email"
        uri = URI(search_url)
        req = Net::HTTP::Get.new(uri)
        req["Accept"] = "application/vnd.github+json"
        req["X-GitHub-Api-Version"] = "2022-11-28"

        resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
        return failure(errors: [ "GitHub search failed: #{resp.code}" ]) unless resp.code.to_i == 200

        results = JSON.parse(resp.body)
        return failure(errors: [ "No GitHub user found" ]) if results["total_count"].to_i.zero?

        # Fetch full profile for the first result
        user_login = results["items"].first["login"]
        profile_resp = fetch_profile(user_login)
        return failure(errors: [ "GitHub profile fetch failed" ]) unless profile_resp

        success(data: profile_resp)
      rescue StandardError => e
        failure(errors: [ "GitHub enrichment error: #{e.message}" ])
      end

      private

      def fetch_profile(login)
        uri = URI("https://api.github.com/users/#{login}")
        req = Net::HTTP::Get.new(uri)
        req["Accept"] = "application/vnd.github+json"
        resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
        return nil unless resp.code.to_i == 200

        JSON.parse(resp.body)
      end
    end
  end
end
