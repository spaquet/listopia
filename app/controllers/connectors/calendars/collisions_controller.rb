module Connectors
  module Calendars
    # Controller for detecting scheduling collisions across calendar accounts
    class CollisionsController < Connectors::BaseController
      before_action :authenticate_user!
      before_action :require_current_organization!

      # POST /connectors/calendars/collisions/check
      # Check for scheduling collisions in the given time range
      def check
        start_time = parse_time_param(params[:start_time])
        end_time = parse_time_param(params[:end_time])

        return render json: { error: "Invalid time format" }, status: :bad_request if start_time.nil? || end_time.nil?
        return render json: { error: "Start time must be before end time" }, status: :bad_request if start_time >= end_time

        result = Connectors::CollisionDetectorService.call(
          user: current_user,
          start_time: start_time,
          end_time: end_time,
          exclude_external_id: params[:exclude_external_id]
        )

        render json: result.data
      rescue StandardError => e
        Rails.logger.error("Collision check failed: #{e.message}")
        render json: { error: "Failed to check collisions" }, status: :internal_server_error
      end

      private

      def require_current_organization!
        redirect_to root_path, alert: "Please select an organization first" unless Current.organization
      end

      def parse_time_param(time_str)
        return nil if time_str.blank?

        begin
          Time.iso8601(time_str)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
