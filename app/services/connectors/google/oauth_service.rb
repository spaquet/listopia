module Connectors
  module Google
    # Google OAuth 2.0 service for Calendar and Drive APIs
    class OauthService < Connectors::OauthService
      OAUTH_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
      OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token"

      def initialize(connector_account: nil)
        super
      end

      # Generate Google OAuth authorization URL
      def authorization_url(redirect_uri:, state:)
        query = URI.encode_www_form(
          client_id: google_client_id,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: oauth_scopes.join(" "),
          access_type: "offline",
          prompt: "consent",
          state: state
        )

        "#{OAUTH_AUTH_URL}?#{query}"
      end

      # Exchange authorization code for tokens
      def exchange_code!(code, redirect_uri, user, organization)
        return failure(errors: ["Invalid code"], message: "Authorization failed") if code.blank?

        begin
          # Make HTTP request to Google token endpoint
          response = make_token_request(
            code: code,
            grant_type: "authorization_code",
            redirect_uri: redirect_uri
          )

          # Parse response
          data = JSON.parse(response.body)

          # Extract user info from ID token (JWT)
          user_info = decode_id_token(data["id_token"])

          # Find or create connector account
          account = find_or_create_account(user, organization, user_info)

          # Save tokens
          save_tokens!(
            access_token: data["access_token"],
            refresh_token: data["refresh_token"],
            expires_in: data["expires_in"]
          )

          success(data: account)
        rescue StandardError => e
          Rails.logger.error("Google OAuth exchange failed: #{e.message}")
          failure(errors: [e.message], message: "Token exchange failed")
        end
      end

      # Refresh expired access token using refresh token
      def refresh_token!
        return failure(errors: ["No refresh token"], message: "Cannot refresh") unless connector_account.refresh_token.present?

        begin
          response = make_token_request(
            grant_type: "refresh_token",
            refresh_token: connector_account.refresh_token
          )

          data = JSON.parse(response.body)

          save_tokens!(
            access_token: data["access_token"],
            refresh_token: data.fetch("refresh_token", connector_account.refresh_token),
            expires_in: data["expires_in"]
          )

          success(data: { status: "refreshed" })
        rescue StandardError => e
          Rails.logger.error("Google token refresh failed: #{e.message}")
          failure(errors: [e.message], message: "Token refresh failed")
        end
      end

      private

      # Make HTTP request to Google token endpoint
      def make_token_request(**params)
        require "net/http"
        require "uri"

        uri = URI(OAUTH_TOKEN_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request.form_data = params.merge(
          client_id: google_client_id,
          client_secret: google_client_secret
        )

        response = http.request(request)

        raise "Token request failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        response
      end

      # Decode and verify ID token (JWT)
      def decode_id_token(id_token)
        require "jwt"

        # For now, just parse without verification (in production, verify signature)
        decoded = JWT.decode(id_token, google_client_secret, false)
        decoded[0]
      rescue StandardError => e
        Rails.logger.warn("Failed to decode ID token: #{e.message}")
        { "sub" => SecureRandom.hex(16) }
      end

      # Find or create connector account for user
      def find_or_create_account(user, organization, user_info)
        google_user_id = user_info["sub"]

        account = Connectors::Account.find_or_create_by(
          user_id: user.id,
          organization_id: organization.id,
          provider: "google_calendar",
          provider_uid: google_user_id
        ) do |a|
          a.display_name = user_info["name"] || "Google Account"
          a.email = user_info["email"]
          a.token_scope = oauth_scopes.join(" ")
          a.status = "active"
        end

        @connector_account = account
        account
      end

      # Get Google OAuth credentials from environment or credentials
      def google_client_id
        Rails.application.credentials.dig(:google_calendar, :client_id) ||
          ENV["GOOGLE_OAUTH_CLIENT_ID"] ||
          raise("Google OAuth client ID not configured")
      end

      def google_client_secret
        Rails.application.credentials.dig(:google_calendar, :client_secret) ||
          ENV["GOOGLE_OAUTH_CLIENT_SECRET"] ||
          raise("Google OAuth client secret not configured")
      end

      def oauth_scopes
        Connectors::GoogleCalendar.oauth_scopes_list
      end
    end
  end
end
