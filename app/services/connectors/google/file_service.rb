module Connectors
  module Google
    # Manage files from Google Drive
    class FileService < Connectors::BaseService
      GOOGLE_DRIVE_API_URL = "https://www.googleapis.com/drive/v3"
      PAGE_SIZE = 50

      # Get about information (user and quota)
      def fetch_about
        with_sync_log(operation: "fetch_about") do |log|
          ensure_fresh_token!

          response = make_google_request(:get, "about", fields: "user,storageQuota")
          data = JSON.parse(response.body)

          raise "Google Drive API error: #{data["error"]["message"]}" if data["error"].present?

          log.update!(records_processed: 1)

          data
        end
      end

      # List files in Google Drive
      def list_files(query: nil, page_token: nil)
        with_sync_log(operation: "list_files") do |log|
          ensure_fresh_token!

          q_param = build_query(query)
          fields = "files(id,name,mimeType,modifiedTime,webViewLink,fileExtension,size,owners),nextPageToken"

          params = {
            q: q_param,
            fields: fields,
            pageSize: PAGE_SIZE,
            pageToken: page_token,
            orderBy: "modifiedTime desc"
          }.compact

          response = make_google_request(:get, "files", params)
          data = JSON.parse(response.body)

          raise "Google Drive API error: #{data["error"]["message"]}" if data["error"].present?

          log.update!(records_processed: data["files"]&.count.to_i)

          {
            files: data["files"] || [],
            next_page_token: data["nextPageToken"]
          }
        end
      end

      # Get file metadata
      def get_file(file_id)
        with_sync_log(operation: "get_file") do |log|
          ensure_fresh_token!

          fields = "id,name,mimeType,modifiedTime,webViewLink,fileExtension,size,owners,parents"
          response = make_google_request(:get, "files/#{file_id}", fields: fields)
          data = JSON.parse(response.body)

          raise "Google Drive API error: #{data["error"]["message"]}" if data["error"].present?

          log.update!(records_processed: 1)

          data
        end
      end

      # Get file download URL
      def get_download_url(file_id)
        file = get_file(file_id)
        "#{GOOGLE_DRIVE_API_URL}/files/#{file_id}?alt=media&key=#{google_api_key}"
      end

      # Export file (for Docs, Sheets, Slides)
      def export_file(file_id, export_mime_type)
        with_sync_log(operation: "export_file") do |log|
          ensure_fresh_token!

          response = make_google_request(:get, "files/#{file_id}/export", mimeType: export_mime_type)

          log.update!(records_processed: 1)

          response.body
        end
      end

      private

      def build_query(search_query)
        queries = ["trashed = false"]
        queries << "name contains '#{search_query}'" if search_query.present?
        queries.join(" and ")
      end

      def make_google_request(method, endpoint, params = {})
        require "net/http"
        require "uri"
        require "json"

        url = "#{GOOGLE_DRIVE_API_URL}/#{endpoint}"
        uri = URI(url)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        if method == :post
          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/json"
          request.body = params.to_json
        else
          uri.query = URI.encode_www_form(params)
          request = Net::HTTP::Get.new(uri)
        end

        request["Authorization"] = "Bearer #{connector_account.access_token}"

        response = http.request(request)

        raise "Google Drive API error: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        response
      end

      def google_api_key
        Rails.application.credentials.dig(:google_calendar, :api_key) ||
          ENV["GOOGLE_API_KEY"]
      end
    end
  end
end
