module Connectors
  # Controller for managing connector accounts
  class ConnectorAccountsController < BaseController
    skip_before_action :load_connector, only: [ :index, :available ]

    # GET /connectors/accounts
    def index
      authorize ::Connectors::Account, policy_class: ::Connectors::AccountPolicy

      @accounts =
        if params[:provider].present?
          policy_scope(::Connectors::Account)
            .for_user(current_user)
            .by_provider(params[:provider])
        else
          policy_scope(::Connectors::Account).for_user(current_user)
        end
      @connectors = ::Connectors::Registry.all
    end

    # GET /connectors/available
    def available
      @connectors = ::Connectors::Registry.all
      render json: @connectors.map { |c| connector_metadata(c) }
    end

    # DELETE /connectors/:id
    def destroy
      @connector_account.destroy!
      redirect_to connectors_connector_accounts_path, notice: "Account disconnected"
    end

    # POST /connectors/:id/test
    def test
      respond_to do |format|
        format.json do
          begin
            connector = build_connector(@connector_account)
            connector.test_connection
            render json: { status: "success", message: "Connection successful" }
          rescue StandardError => e
            render json: { status: "error", message: e.message }, status: :bad_request
          end
        end
      end
    end

    # PATCH /connectors/:id/pause
    def pause
      @connector_account.update!(status: :paused)
      redirect_to connectors_connector_accounts_path, notice: "Account paused"
    end

    # PATCH /connectors/:id/resume
    def resume
      @connector_account.update!(status: :active)
      redirect_to connectors_connector_accounts_path, notice: "Account resumed"
    end

    private

    def connector_metadata(connector_class)
      {
        key: connector_class.key,
        name: connector_class.name,
        category: connector_class.category,
        icon: connector_class.icon,
        description: connector_class.description
      }
    end
  end
end
