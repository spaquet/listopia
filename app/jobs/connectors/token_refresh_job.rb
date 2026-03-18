module Connectors
  # Job to proactively refresh tokens before they expire
  # Runs on a schedule to ensure tokens stay fresh
  class TokenRefreshJob < BaseJob
    protected

    def call
      return if connector_account.refresh_token.blank?
      return unless connector_account.token_expires_at.present?
      return unless connector_account.token_expires_at < 1.hour.from_now

      # Find the provider's OAuth service class
      provider_service_class = find_oauth_service_class(connector_account.provider)
      return unless provider_service_class

      # Set Current context for authorization checks
      Current.user = connector_account.user
      Current.organization = connector_account.organization

      refresh_service = provider_service_class.new(
        connector_account: connector_account
      )

      result = refresh_service.refresh_token!

      if result.failure?
        Rails.logger.warn("Token refresh failed for #{connector_account.provider}: #{result.message}")
      end
    ensure
      Current.reset
    end

    private

    def find_oauth_service_class(provider)
      # Try to find provider-specific service
      # e.g., Connectors::GoogleCalendar::OauthService
      service_class_name = "::Connectors::#{provider.classify}::OauthService"
      begin
        service_class_name.constantize
      rescue NameError
        # Fall back to stub for testing
        "stub".include?(provider) ? ::Connectors::Stub::OauthService : nil
      end
    end
  end
end
