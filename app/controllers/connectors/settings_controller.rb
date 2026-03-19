module Connectors
  # Controller for connector settings
  class SettingsController < BaseController
    before_action :set_connector_account, only: [ :show, :update ]

    # GET /connectors/settings/:connector_account_id
    def show
      @connector = build_connector(@connector_account)
      @schema = @connector.class.schema
      @settings = @connector_account.settings.index_by(&:key)
    end

    # PATCH /connectors/settings/:connector_account_id
    def update
      @connector = build_connector(@connector_account)
      @schema = @connector.class.schema

      # Save settings from params
      if params[:settings].present?
        params[:settings].each do |key, value|
          next unless @schema.key?(key.to_sym)
          @connector_account.settings.find_or_create_by(key: key).update!(value: value)
        end
      end

      redirect_to connectors_setting_path(@connector_account), notice: "Settings saved"
    end

    private

    def set_connector_account
      @connector_account = ::Connectors::Account.find(params[:connector_account_id])
      authorize @connector_account, policy_class: ::Connectors::AccountPolicy
    end
  end
end
