module Connectors
  module Calendars
    class ConflictsController < ApplicationController
      before_action :authenticate_user!

      def index
        @organization = Current.organization
        redirect_to root_path, alert: "Please select an organization first" and return unless @organization

        result = CalendarConflictScanService.new(
          user: current_user, organization: @organization
        ).call

        @conflicts = result.success? ? result.data : []
      end
    end
  end
end
