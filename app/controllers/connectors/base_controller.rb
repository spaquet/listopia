module Connectors
  # Base controller for all connector routes
  class BaseController < ApplicationController
    before_action :authenticate_user!
    before_action :load_connector, only: [ :show, :update, :test, :pause, :resume, :destroy ]

    protected

    # Load a connector account from the route params
    def load_connector
      @connector_account = ::Connectors::Account.find(params[:connector_account_id] || params[:id])
      authorize @connector_account, policy_class: ::Connectors::AccountPolicy
    end

    # Get the connector class from the registry
    def find_connector_class(provider)
      ::Connectors::Registry.find(provider) ||
        (raise "Unknown connector: #{provider}")
    end

    # Create a connector instance
    def build_connector(account)
      connector_class = find_connector_class(account.provider)
      connector_class.new(account)
    end
  end
end
