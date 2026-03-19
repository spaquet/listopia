module Connectors
  # Base job class for connector operations
  # Jobs operate in system context without user auth, so verify account exists and is valid
  class BaseJob < ApplicationJob
    attr_reader :connector_account

    def perform(connector_account_id:, **options)
      @connector_account = ::Connectors::Account.find(connector_account_id)

      # Verify account exists and is accessible (not deleted, belongs to valid user/org)
      raise "Connector account not found" unless @connector_account
      raise "Connector account belongs to non-existent user" unless @connector_account.user.present?
      raise "Connector account belongs to non-existent organization" unless @connector_account.organization.present?

      call(**options)
    rescue StandardError => e
      handle_error(e)
      raise
    end

    protected

    def call(**options)
      raise NotImplementedError, "Subclasses must implement #call"
    end

    def handle_error(error)
      connector_account.update!(
        status: :errored,
        last_error: error.message,
        error_count: connector_account.error_count + 1
      )

      Rails.logger.error("Connector job failed for #{connector_account.provider}: #{error.message}")
    end
  end
end
