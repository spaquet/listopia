module Connectors
  # OAuth flow controller for all providers
  # Handles OAuth authorization and token exchange with CSRF protection
  class OauthController < BaseController
    skip_before_action :load_connector
    before_action :validate_state, only: :callback

    # GET /connectors/oauth/:provider/authorize
    def authorize
      authenticate_user!

      @connector_class = find_connector_class(params[:provider])
      raise "Provider does not support OAuth" unless @connector_class.oauth_required?

      # Generate state parameter for CSRF protection
      state = SecureRandom.urlsafe_base64
      session[:oauth_state] = state

      # Build authorization URL - this will be overridden per-provider in subclasses
      # For now, we'll redirect to a provider-specific implementation
      provider_service = "::Connectors::#{params[:provider].classify}::OauthService".constantize
      redirect_to provider_service.new.authorization_url(
        redirect_uri: oauth_callback_url,
        state: state
      )
    rescue NameError
      redirect_to connectors_connector_accounts_path, alert: "OAuth not configured for this provider"
    end

    # GET /connectors/oauth/:provider/callback
    def callback
      authenticate_user!

      code = params[:code]
      error = params[:error]
      error_description = params[:error_description]

      if error.present?
        redirect_to connectors_connector_accounts_path,
          alert: "Authorization failed: #{error_description}"
        return
      end

      unless code.present?
        redirect_to connectors_connector_accounts_path, alert: "No authorization code received"
        return
      end

      # Exchange code for tokens - provider-specific
      begin
        provider_service = "::Connectors::#{params[:provider].classify}::OauthService".constantize
        service = provider_service.new
        result = service.exchange_code!(
          code,
          oauth_callback_url,
          current_user,
          current_organization
        )

        if result.success?
          redirect_to connectors_setting_path(result.data),
            notice: "Account connected successfully"
        else
          redirect_to connectors_connector_accounts_path,
            alert: "Failed to connect account: #{result.message}"
        end
      rescue StandardError => e
        redirect_to connectors_connector_accounts_path,
          alert: "Connection failed: #{e.message}"
      end
    end

    private

    def oauth_callback_url
      connectors_oauth_callback_url(provider: params[:provider])
    end

    # Validate CSRF state parameter
    def validate_state
      return if params[:state].blank? # error case, handled elsewhere

      unless params[:state] == session.delete(:oauth_state)
        redirect_to connectors_connector_accounts_path, alert: "Invalid OAuth state - possible CSRF attack"
      end
    end
  end
end
