module Connectors
  module Calendars
    module Google
      # Controller for Google Calendar events
      class EventsController < Connectors::BaseController
        before_action :load_connector_account

        # GET /connectors/calendars/google/events
        def index
          @events = fetch_calendar_events
          authorize @connector_account
        end

        # POST /connectors/calendars/google/events/sync
        def sync
          authorize @connector_account

          # Trigger event sync job
          ::Connectors::Calendars::Google::SyncJob.perform_later(
            connector_account_id: @connector_account.id
          )

          redirect_to connectors_calendars_google_events_path, notice: "Sync started"
        end

        private

        def load_connector_account
          @connector_account = ::Connectors::Account.find(params[:connector_account_id])
          authorize @connector_account, policy_class: ::Connectors::AccountPolicy
        end

        def fetch_calendar_events
          service = ::Connectors::Google::EventSyncService.new(
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
