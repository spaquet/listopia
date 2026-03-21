module Connectors
  module Calendars
    class CalendarConflictScanService < ApplicationService
      def initialize(user:, organization:, lookahead: 14.days)
        @user = user
        @organization = organization
        @lookahead = lookahead
      end

      def call
        events = CalendarEvent
          .where(user_id: @user.id, organization_id: @organization.id)
          .where.not(status: "cancelled")
          .where(start_time: Time.current..(Time.current + @lookahead))
          .where.not(end_time: nil)
          .order(:start_time)

        conflicts = []
        events_arr = events.to_a
        events_arr.each_with_index do |a, i|
          events_arr[(i + 1)..].each do |b|
            break if b.start_time >= a.end_time   # sorted, no more overlaps possible
            conflicts << { event: a, overlapping_event: b }
          end
        end

        success(data: conflicts)
      end
    end
  end
end
