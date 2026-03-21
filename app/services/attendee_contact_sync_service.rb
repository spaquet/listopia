class AttendeeContactSyncService < ApplicationService
  def initialize(calendar_event:, organization:)
    @calendar_event = calendar_event
    @organization = organization
  end

  def call
    attendees = @calendar_event.attendees || []
    attendees.each { |a| upsert_contact(a) }
    success(data: attendees.size)
  end

  private

  def upsert_contact(attendee)
    email = attendee["email"].to_s.downcase.strip
    return if email.blank?

    contact = AttendeeContact.find_or_initialize_by(
      organization_id: @organization.id,
      email: email
    )

    # Update display_name only if not already enriched
    contact.display_name ||= attendee["displayName"]

    # Cross-reference with Listopia users
    contact.user_id ||= User.find_by(email: email)&.id

    if contact.new_record?
      contact.enrichment_status = :pending
      contact.save!
      EnrichAttendeeContactJob.perform_later(attendee_contact_id: contact.id)
    else
      contact.save! if contact.changed?
    end
  end
end
