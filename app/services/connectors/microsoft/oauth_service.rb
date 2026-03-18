module Connectors
  module Microsoft
    # Microsoft OAuth 2.0 service for Outlook Calendar API
    # Uses Microsoft Identity Platform v2.0 with PKCE
    class OauthService < Connectors::OauthService
      OAUTH_AUTH_URL = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
      OAUTH_TOKEN_URL = "https://login.microsoftonline.com/common/oauth2/v2.0/token"
      GRAPH_API_URL = "https://graph.microsoft.com/v1.0"

      def initialize(connector_account: nil)
        super
      end

      # Generate Microsoft OAuth authorization URL with PKCE
      def authorization_url(redirect_uri:, state:)
        # Generate PKCE challenge
        code_verifier = SecureRandom.urlsafe_base64(32)
        code_challenge = Base64.urlsafe_encode64(
          Digest::SHA256.digest(code_verifier)
        ).tr("=", "")

        # Store verifier in session (will be used in callback)
        # Note: In actual implementation, pass via session or temporary storage
        query = URI.encode_www_form(
          client_id: microsoft_client_id,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: oauth_scopes.join(" "),
          state: state,
          code_challenge: code_challenge,
          code_challenge_method: "S256"
        )

        "#{OAUTH_AUTH_URL}?#{query}"
      end

      # Exchange authorization code for tokens
      def exchange_code!(code, redirect_uri, user, organization)
        return failure(errors: ["Invalid code"], message: "Authorization failed") if code.blank?

        begin
          # Make HTTP request to Microsoft token endpoint
          response = make_token_request(
            code: code,
            grant_type: "authorization_code",
            redirect_uri: redirect_uri
          )

          # Parse response
          data = JSON.parse(response.body)

          # Fetch user info from Microsoft Graph
          user_info = fetch_user_info(data["access_token"])

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
          Rails.logger.error("Microsoft OAuth exchange failed: #{e.message}")
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
          Rails.logger.error("Microsoft token refresh failed: #{e.message}")
          failure(errors: [e.message], message: "Token refresh failed")
        end
      end

      private

      # Make HTTP request to Microsoft token endpoint
      def make_token_request(**params)
        require "net/http"
        require "uri"

        uri = URI(OAUTH_TOKEN_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request.form_data = params.merge(
          client_id: microsoft_client_id,
          client_secret: microsoft_client_secret
        )

        response = http.request(request)

        raise "Token request failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        response
      end

      # Fetch user info from Microsoft Graph
      def fetch_user_info(access_token)
        require "net/http"
        require "uri"

        uri = URI("#{GRAPH_API_URL}/me")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{access_token}"

        response = http.request(request)

        raise "Failed to fetch user info" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end

      # Find or create connector account for user
      def find_or_create_account(user, organization, user_info)
        microsoft_user_id = user_info["id"]

        account = Connectors::Account.find_or_create_by(
          user_id: user.id,
          organization_id: organization.id,
          provider: "microsoft_outlook",
          provider_uid: microsoft_user_id
        ) do |a|
          a.display_name = user_info["displayName"] || "Outlook Account"
          a.email = user_info["userPrincipalName"] || user_info["mail"]
          a.token_scope = oauth_scopes.join(" ")
          a.status = "active"
        end

        @connector_account = account
        account
      end

      # Get Microsoft OAuth credentials
      def microsoft_client_id
        Rails.application.credentials.dig(:microsoft_outlook, :client_id) ||
          ENV["MICROSOFT_OAUTH_CLIENT_ID"] ||
          raise("Microsoft OAuth client ID not configured")
      end

      def microsoft_client_secret
        Rails.application.credentials.dig(:microsoft_outlook, :client_secret) ||
          ENV["MICROSOFT_OAUTH_CLIENT_SECRET"] ||
          raise("Microsoft OAuth client secret not configured")
      end

      def oauth_scopes
        Connectors::MicrosoftOutlook.oauth_scopes_list
      end
    end
  end
end
