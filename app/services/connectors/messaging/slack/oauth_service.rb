module Connectors
  module Messaging
    module Slack
      # Slack OAuth 2.0 service
      # https://api.slack.com/authentication/oauth-v2
      class OauthService < Connectors::OauthService
      OAUTH_AUTH_URL = "https://slack.com/oauth_authorize"
      OAUTH_TOKEN_URL = "https://slack.com/api/oauth.v2.access"
      SLACK_API_URL = "https://slack.com/api"

      def initialize(connector_account: nil)
        super
      end

      # Generate Slack OAuth authorization URL
      def authorization_url(redirect_uri:, state:)
        query = URI.encode_www_form(
          client_id: slack_client_id,
          scope: oauth_scopes.join(","),
          redirect_uri: redirect_uri,
          state: state,
          user_scope: "users:read"  # User-level scopes
        )

        "#{OAUTH_AUTH_URL}?#{query}"
      end

      # Exchange authorization code for tokens
      def exchange_code!(code, redirect_uri, user, organization)
        return failure(errors: ["Invalid code"], message: "Authorization failed") if code.blank?

        begin
          response = make_slack_request(
            :post,
            "oauth.v2.access",
            code: code,
            client_id: slack_client_id,
            client_secret: slack_client_secret,
            redirect_uri: redirect_uri
          )

          data = JSON.parse(response.body)

          unless data["ok"]
            return failure(errors: [data["error"]], message: "Slack authorization failed")
          end

          # Fetch workspace and user info
          workspace_info = fetch_workspace_info(data["access_token"])

          # Find or create connector account
          account = find_or_create_account(user, organization, data, workspace_info)

          # Save tokens (Slack doesn't provide refresh tokens for bot apps)
          save_tokens!(
            access_token: data["access_token"],
            refresh_token: nil,
            expires_in: nil  # Slack bot tokens don't expire
          )

          success(data: account)
        rescue StandardError => e
          Rails.logger.error("Slack OAuth exchange failed: #{e.message}")
          failure(errors: [e.message], message: "Token exchange failed")
        end
      end

      # Slack tokens don't typically expire, so refresh is a no-op
      def refresh_token!
        return success(data: { status: "no_refresh_needed" }) unless connector_account.token_expired?

        # In case token needs rotation in future
        success(data: { status: "refreshed" })
      end

      private

      # Make HTTP request to Slack API
      def make_slack_request(method, endpoint, **params)
        require "net/http"
        require "uri"

        url = "#{SLACK_API_URL}/#{endpoint}"
        uri = URI(url)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        if method == :post
          request = Net::HTTP::Post.new(uri)
          request.form_data = params
        else
          uri.query = URI.encode_www_form(params)
          request = Net::HTTP::Get.new(uri)
        end

        response = http.request(request)

        raise "Slack API error: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        response
      end

      # Fetch workspace info from Slack
      def fetch_workspace_info(access_token)
        response = make_slack_request(
          :get,
          "auth.test",
          token: access_token
        )

        JSON.parse(response.body)
      end

      # Find or create connector account
      def find_or_create_account(user, organization, oauth_data, workspace_info)
        team_id = workspace_info["team_id"]

        account = Connectors::Account.find_or_create_by(
          user_id: user.id,
          organization_id: organization.id,
          provider: "slack",
          provider_uid: team_id
        ) do |a|
          a.display_name = workspace_info["team"] || "Slack Workspace"
          a.email = workspace_info["user_id"]
          a.token_scope = oauth_scopes.join(",")
          a.status = "active"
          a.metadata = {
            app_id: oauth_data["app_id"],
            team_id: team_id,
            team_name: workspace_info["team"]
          }
        end

        @connector_account = account
        account
      end

      # Get Slack OAuth credentials
      def slack_client_id
        Rails.application.credentials.dig(:slack, :client_id) ||
          ENV["SLACK_CLIENT_ID"] ||
          raise("Slack client ID not configured")
      end

      def slack_client_secret
        Rails.application.credentials.dig(:slack, :client_secret) ||
          ENV["SLACK_CLIENT_SECRET"] ||
          raise("Slack client secret not configured")
      end

      def oauth_scopes
        Connectors::Slack.oauth_scopes_list
      end
    end
  end
end
