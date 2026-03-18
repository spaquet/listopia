module Connectors
  module Calendars
    module Google
      # Controller for Google Calendar management
      class CalendarsController < Connectors::BaseController
        before_action :load_connector_account

        # GET /connectors/calendars/google/calendars
        def index
          @calendars = fetch_user_calendars
          authorize @connector_account
        end

        # POST /connectors/calendars/google/calendars/select
        def select
          authorize @connector_account

          calendar_id = params[:calendar_id]
          return redirect_to(connectors_connector_accounts_path, alert: "Calendar ID required") if calendar_id.blank?

          # Save selected calendar to settings
          setting = @connector_account.settings.find_or_create_by(key: "default_calendar_id")
          setting.update!(value: calendar_id)

          redirect_to connectors_calendars_google_events_path, notice: "Calendar selected"
        end

        private

        def load_connector_account
          @connector_account = ::Connectors::Account.find(params[:connector_account_id])
          authorize @connector_account, policy_class: ::Connectors::AccountPolicy
        end

        def fetch_user_calendars
          service = ::Connectors::Google::CalendarFetchService.new(
            connector_account: @connector_account
          )

          begin
            service.fetch_calendars
          rescue StandardError => e
            Rails.logger.error("Failed to fetch calendars: #{e.message}")
            []
          end
        end
      end
    end
  end
end
