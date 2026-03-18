module Connectors
  # Base service for OAuth token management
  # Handles token exchange, refresh, and revocation
  class OauthService < ApplicationService
    attr_reader :connector_account

    def initialize(connector_account: nil)
      @connector_account = connector_account
    end

    # Exchange authorization code for access token
    # Subclasses should override this method with provider-specific logic
    def exchange_code!(code, redirect_uri, user, organization)
      raise NotImplementedError, "Subclasses must implement #exchange_code!"
    end

    # Refresh an expired access token using refresh token
    # Subclasses should override this method with provider-specific logic
    def refresh_token!
      raise NotImplementedError, "Subclasses must implement #refresh_token!"
    end

    # Revoke the connector account's tokens
    # Called when user disconnects the account
    def revoke!
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

    # Helper to create a signed state parameter for CSRF protection
    def generate_state
      SecureRandom.urlsafe_base64
    end

    # Helper to verify state parameter hasn't been tampered with
    def verify_state(state, session_state)
      state == session_state
    end

    # Save tokens to connector account with expiration
    def save_tokens!(access_token:, refresh_token: nil, expires_in: nil)
      return unless connector_account

      connector_account.update!(
        access_token: access_token,
        refresh_token: refresh_token,
        token_expires_at: expires_in ? Time.current + expires_in.seconds : nil,
        status: :active,
        last_sync_at: Time.current,
        error_count: 0,
        last_error: nil
      )
    end
  end
end
