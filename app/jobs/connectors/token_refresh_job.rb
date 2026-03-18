module Connectors
  # Job to refresh tokens before expiry
  class TokenRefreshJob < BaseJob
    protected

    def call
      return if connector_account.refresh_token.blank?
      return unless connector_account.token_expires_at.present?
      return unless connector_account.token_expires_at < 1.hour.from_now

      refresh_service = ::Connectors::OauthService.new(
        connector_account: connector_account
      )

      refresh_service.refresh_token!
    end
  end
end
