class AttendeeEnrichmentService < ApplicationService
  def initialize(attendee_contact:)
    @contact = attendee_contact
  end

  def call
    enriched = false

    # Try Clearbit first (most comprehensive)
    clearbit = Connectors::Clearbit::EnrichmentService.new(email: @contact.email).call
    if clearbit.success?
      @contact.apply_clearbit(clearbit.data)
      enriched = true
    end

    # Try GitHub (public API, no key needed)
    github = Connectors::GitHub::EnrichmentService.new(email: @contact.email).call
    if github.success?
      @contact.apply_github(github.data)
      enriched = true
    end

    @contact.enrichment_status = enriched ? :enriched : :failed
    @contact.enriched_at = Time.current
    @contact.save!

    success(data: @contact)
  rescue StandardError => e
    @contact.update!(enrichment_status: :failed, enriched_at: Time.current)
    failure(errors: [ e.message ])
  end
end
