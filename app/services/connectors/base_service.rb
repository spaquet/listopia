module Connectors
  # Base service class for connector operations
  # Adds connector context and sync logging
  # All operations require authenticated user context and ownership
  class BaseService < ApplicationService
    attr_reader :connector_account

    def initialize(connector_account:)
      raise "User must be authenticated" unless Current.user.present?
      raise "User does not own this connector account" unless connector_account.user_id == Current.user.id

      @connector_account = connector_account
    end

    protected

    # Get the connector instance for this service
    def connector
      @connector ||= begin
        connector_class = ::Connectors::Registry.find(connector_account.provider)
        raise "Unknown connector: #{connector_account.provider}" unless connector_class
        connector_class.new(connector_account)
      end
    end

    # Wrap an operation with sync logging
    def with_sync_log(operation:)
      log = connector_account.sync_logs.create!(
        operation: operation,
        status: :in_progress,
        started_at: Time.current
      )

      begin
        result = yield(log)

        log.update!(
          status: :success,
          completed_at: Time.current,
          duration_ms: ((Time.current - log.started_at) * 1000).to_i
        )

        result
      rescue StandardError => e
        log.update!(
          status: :failure,
          error_message: e.message,
          completed_at: Time.current,
          duration_ms: ((Time.current - log.started_at) * 1000).to_i
        )

        connector_account.update!(
          last_error: e.message,
          error_count: connector_account.error_count + 1,
          status: :errored
        )

        raise
      end
    end

    # Ensure the token is fresh before making API calls
    def ensure_fresh_token!
      return unless connector_account.token_expired?

      refresh_service = ::Connectors::OauthService.new(
        connector_account: connector_account
      )
      refresh_service.refresh_token!
    end
  end
end
