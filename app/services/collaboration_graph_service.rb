class CollaborationGraphService < ApplicationService
  def initialize(user:, organization:, since: 90.days.ago, limit: 50)
    @user = user
    @organization = organization
    @since = since
    @limit = limit
  end

  def call
    # Find all user's calendar events in the date range
    user_events = CalendarEvent
      .where(user_id: @user.id, organization_id: @organization.id)
      .where(start_time: @since..)
      .where.not(attendees: nil)

    # Build collaboration counts from attendees
    collaborations = Hash.new { |h, k| h[k] = { count: 0, last_together: nil } }

    user_events.each do |event|
      event.attendees.each do |attendee|
        email = attendee["email"].to_s.downcase
        next if email == @user.email.downcase

        collaborations[email][:count] += 1
        event_time = event.start_time
        if collaborations[email][:last_together].nil? || event_time > collaborations[email][:last_together]
          collaborations[email][:last_together] = event_time
        end
      end
    end

    # Sort by count descending, limit
    top = collaborations
      .sort_by { |_, v| -v[:count] }
      .first(@limit)

    # Load AttendeeContact records for enrichment data
    emails = top.map(&:first)
    contacts = AttendeeContact
      .where(organization_id: @organization.id, email: emails)
      .index_by(&:email)

    results = top.map do |email, stats|
      contact = contacts[email] || AttendeeContact.new(email: email, display_name: email)
      {
        contact: contact,
        shared_meetings: stats[:count],
        last_together: stats[:last_together]
      }
    end

    success(data: results)
  end
end
