module Connectors
  module Messaging
    module Slack
      # Controller for Slack channel management
      class ChannelsController < Connectors::BaseController
        before_action :load_connector_account

        # GET /connectors/messaging/slack/channels
        def index
          @channels = fetch_slack_channels
          authorize @connector_account
        end

        # POST /connectors/messaging/slack/channels/select
        def select
          authorize @connector_account

          channel_id = params[:channel_id]
          return redirect_to(connectors_connector_accounts_path, alert: "Channel ID required") if channel_id.blank?

          # Save selected channel to settings
          setting = @connector_account.settings.find_or_create_by(key: "default_channel_id")
          setting.update!(value: channel_id)

          redirect_to connectors_settings_path(@connector_account), notice: "Default channel updated"
        end

        private

        def load_connector_account
          @connector_account = ::Connectors::Account.find(params[:connector_account_id])
          authorize @connector_account, policy_class: ::Connectors::AccountPolicy
        end

        def fetch_slack_channels
          service = ::Connectors::Slack::MessageService.new(
            connector_account: @connector_account
          )

          begin
            service.fetch_channels
          rescue StandardError => e
            Rails.logger.error("Failed to fetch Slack channels: #{e.message}")
            []
          end
        end
      end
    end
  end
end
