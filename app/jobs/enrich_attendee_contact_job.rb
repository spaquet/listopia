class EnrichAttendeeContactJob < ApplicationJob
  queue_as :default

  def perform(attendee_contact_id:)
    contact = AttendeeContact.find(attendee_contact_id)
    AttendeeEnrichmentService.new(attendee_contact: contact).call
  rescue ActiveRecord::RecordNotFound
    # Contact deleted — nothing to do
  end
end
