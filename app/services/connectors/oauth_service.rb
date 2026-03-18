module Connectors
  # Service for OAuth token management
  class OauthService < ApplicationService
    attr_reader :connector_account

    def initialize(connector_account:)
      @connector_account = connector_account
    end

    def exchange_code!(code, redirect_uri)
      # This will be implemented by subclasses specific to each OAuth provider
      raise NotImplementedError
    end

    def refresh_token!
      # This will be implemented by subclasses specific to each OAuth provider
      raise NotImplementedError
    end

    def revoke!
      connector_account.update!(
        status: :revoked,
        access_token_encrypted: nil,
        refresh_token_encrypted: nil
      )
      success(data: { status: :revoked })
    end
  end
end
