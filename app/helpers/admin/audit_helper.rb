module Admin::AuditHelper
  # Query helpers for audit trail combining Logidze + Event model
  # All queries are organization-scoped for multi-tenant safety

  # Get all changes to a resource with actor information
  def audit_trail_for(resource, organization = nil)
    organization ||= resource.organization if resource.respond_to?(:organization)
    org_id = organization.is_a?(Organization) ? organization.id : organization

    AuditTrail.new(resource, org_id)
  end

  # Get events for an organization with filtering
  def organization_events(organization, filters = {})
    scope = Event.where(organization_id: organization.id)

    scope = scope.by_type(filters[:event_type]) if filters[:event_type]
    scope = scope.by_actor(filters[:actor]) if filters[:actor]
    scope = scope.since(filters[:since]) if filters[:since]

    scope.recent
  end

  # Get changes to a specific field across all records in an organization
  def field_change_audit(organization, model_class, field_name, days = 30)
    events = Event.where(organization_id: organization.id)
                  .where("event_data->>'#{model_class.to_s.tableize}' IS NOT NULL")
                  .since(days.days.ago)

    events.select do |event|
      changes = event.event_data["changes"]
      changes&.key?(field_name)
    end
  end

  # Generate compliance report: who changed what when
  def compliance_report(organization, options = {})
    start_date = options[:start_date] || 90.days.ago
    end_date = options[:end_date] || Time.current
    event_types = options[:event_types] || %w[list_item.updated list.updated user.updated]

    events = Event.where(organization_id: organization.id)
                  .where(event_type: event_types)
                  .where("created_at >= ? AND created_at <= ?", start_date, end_date)
                  .recent

    ComplianceReport.new(organization, events, options)
  end

  # Get all changes by a specific user in an organization
  def user_activity_log(organization, user, days = 30)
    Event.where(organization_id: organization.id)
         .by_actor(user)
         .since(days.days.ago)
         .recent
  end

  # Get sensitive field changes (status, priority, access, ownership)
  def sensitive_changes_log(organization, days = 30)
    SENSITIVE_FIELDS = %w[status priority assigned_user_id access is_public].freeze

    events = Event.where(organization_id: organization.id)
                  .where(event_type: %w[list_item.updated list.updated])
                  .since(days.days.ago)

    events.select do |event|
      changes = event.event_data["changes"]
      changes&.keys&.any? { |k| k.in?(SENSITIVE_FIELDS) }
    end
  end

  # Get events in a time range with summaries
  def audit_summary(organization, start_date = 30.days.ago, end_date = Time.current)
    events = Event.where(organization_id: organization.id)
                  .where("created_at >= ? AND created_at <= ?", start_date, end_date)

    {
      total_events: events.count,
      events_by_type: events.group_by(&:event_type).transform_values(&:count),
      events_by_actor: events.select { |e| e.actor.present? }.group_by { |e| e.actor.email }.transform_values(&:count),
      timeline: events.group_by { |e| e.created_at.to_date }.transform_values(&:count)
    }
  end

  # Export audit trail as CSV
  def export_audit_trail_csv(organization, days = 30)
    events = Event.where(organization_id: organization.id)
                  .since(days.days.ago)
                  .recent

    CSV.generate do |csv|
      csv << ["Timestamp", "User", "Event Type", "Details", "Changes"]

      events.each do |event|
        csv << [
          event.created_at.to_s,
          event.actor&.email || "System",
          event.event_type,
          format_event_data(event),
          format_changes(event)
        ]
      end
    end
  end

  private

  def format_event_data(event)
    case event.event_type
    when "list_item.created"
      "Created: #{event.event_data['title']}"
    when "list_item.deleted"
      "Deleted: #{event.event_data['title']}"
    when "list_item.assigned"
      "Assigned to user #{event.event_data['assigned_user_id']}"
    else
      event.event_type
    end
  end

  def format_changes(event)
    event.event_data["changes"]&.to_json || ""
  end
end
