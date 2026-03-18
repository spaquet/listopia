module Connectors
  module Stub
    # Stub OAuth service for testing connector flows
    # Simulates a real OAuth provider (Google, Slack, etc.)
    class OauthService < Connectors::OauthService
      STUB_CLIENT_ID = "stub_client_id_12345"
      STUB_CLIENT_SECRET = "stub_client_secret_67890"
      STUB_AUTH_URL = "https://stub-oauth-provider.test/oauth/authorize"
      STUB_TOKEN_URL = "https://stub-oauth-provider.test/oauth/token"

      # Build authorization URL for stub provider
      def authorization_url(redirect_uri:, state:)
        uri = URI(STUB_AUTH_URL)
        uri.query = URI.encode_www_form(
          client_id: STUB_CLIENT_ID,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: "read write",
          state: state
        )
        uri.to_s
      end

      # Exchange authorization code for tokens
      def exchange_code!(code, redirect_uri, user, organization)
        # In real implementation, would make HTTP request to provider
        # For stub, we generate fake tokens
        if code.blank? || code == "invalid_code"
          return failure(errors: [ "Invalid authorization code" ], message: "Authorization failed")
        end

        # Create connector account if it doesn't exist
        account = find_or_create_account(user, organization, code)

        # Save tokens
        save_tokens!(
          access_token: generate_stub_token("access", account.provider_uid),
          refresh_token: generate_stub_token("refresh", account.provider_uid),
          expires_in: 3600
        )

        success(data: account)
      rescue StandardError => e
        failure(errors: [ e.message ], message: "Token exchange failed")
      end

      # Refresh expired access token
      def refresh_token!
        return unless connector_account
        return unless connector_account.refresh_token.present?

        # Simulate token refresh
        new_access_token = generate_stub_token("access", connector_account.provider_uid)

        save_tokens!(
          access_token: new_access_token,
          refresh_token: connector_account.refresh_token,
          expires_in: 3600
        )

        success(data: { status: :refreshed })
      rescue StandardError => e
        failure(errors: [ e.message ], message: "Token refresh failed")
      end

      # Revoke tokens at stub provider
      def revoke!
        # Stub doesn't need to revoke at provider
        # Just clear local tokens
        return unless connector_account

        connector_account.update!(
          status: :revoked,
          access_token_encrypted: nil,
          refresh_token_encrypted: nil,
          token_expires_at: nil
        )

        success(data: { status: :revoked })
      end

      protected

      # Find or create a connector account for stub provider
      def find_or_create_account(user, organization, code)
        # Extract stub user ID from code (for testing purposes)
        stub_user_id = code.include?("user:") ? code.split("user:").last : "stub_user_#{SecureRandom.hex(8)}"

        account = Connectors::Account.find_or_create_by(
          user_id: user.id,
          organization_id: organization.id,
          provider: "stub",
          provider_uid: stub_user_id
        ) do |a|
          a.display_name = "Stub Account (#{stub_user_id})"
          a.email = "stub@example.test"
          a.token_scope = "read write"
          a.status = "active"
        end

        @connector_account = account
        account
      end

      # Generate a stub token for testing
      def generate_stub_token(type, user_id)
        payload = {
          type: type,
          user_id: user_id,
          iat: Time.current.to_i,
          exp: (Time.current + 1.hour).to_i
        }

        # Simple base64 encoding for stub (not cryptographically secure)
        Base64.urlsafe_encode64(payload.to_json).tr("=", "")
      end
    end
  end
end
