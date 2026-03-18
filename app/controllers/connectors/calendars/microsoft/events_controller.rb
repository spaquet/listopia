module Connectors
  module Calendars
    module Microsoft
      # Controller for Outlook Calendar events
      class EventsController < Connectors::BaseController
        before_action :load_connector_account

        # GET /connectors/calendars/microsoft/events
        def index
          @events = fetch_calendar_events
          authorize @connector_account
        end

        # POST /connectors/calendars/microsoft/events/sync
        def sync
          authorize @connector_account

          # Trigger event sync job
          ::Connectors::Calendars::Microsoft::SyncJob.perform_later(
            connector_account_id: @connector_account.id
          )

          redirect_to connectors_calendars_microsoft_events_path, notice: "Sync started"
        end

        private

        def load_connector_account
          @connector_account = ::Connectors::Account.find(params[:connector_account_id])
          authorize @connector_account, policy_class: ::Connectors::AccountPolicy
        end

        def fetch_calendar_events
          service = ::Connectors::Microsoft::EventSyncService.new(
            connector_account: @connector_account
          )

          begin
            result = service.pull_events
            result[:events] || []
          rescue StandardError => e
            Rails.logger.error("Failed to fetch events: #{e.message}")
            []
          end
        end
      end
    end
  end
end
