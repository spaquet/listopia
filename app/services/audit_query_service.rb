# Service for querying audit data
# Centralizes all audit trail queries used by controllers and views

class AuditQueryService
  attr_reader :organization

  def initialize(organization)
    @organization = organization
  end

  # Get summary statistics for a date range
  def audit_summary(start_date = 30.days.ago, end_date = Time.current)
    events = Event.where(organization_id: organization.id)
                  .where("created_at >= ? AND created_at <= ?", start_date, end_date)

    {
      total_events: events.count,
      events_by_type: events.group_by(&:event_type).transform_values(&:count),
      events_by_actor: events.select { |e| e.actor.present? }.group_by { |e| e.actor.email }.transform_values(&:count),
      timeline: events.group_by { |e| e.created_at.to_date }.transform_values(&:count)
    }
  end

  # Get events with optional filters
  def organization_events(filters = {}, limit: nil)
    scope = Event.where(organization_id: organization.id)

    scope = scope.by_type(filters[:event_type]) if filters[:event_type]
    scope = scope.by_actor(filters[:actor]) if filters[:actor]
    scope = scope.since(filters[:since]) if filters[:since]

    scope = scope.recent
    scope = scope.limit(limit) if limit

    scope
  end

  # Get sensitive field changes
  def sensitive_changes_log(days = 30)
    events = Event.where(organization_id: organization.id)
                  .where(event_type: %w[list_item.updated list.updated])
                  .since(days.days.ago)

    events.select do |event|
      changes = event.event_data["changes"]
      changes&.keys&.any? { |k| k.in?(Admin::AuditHelper::SENSITIVE_FIELDS) }
    end
  end

  # Get all changes by a specific user
  def user_activity_log(user, days = 30)
    Event.where(organization_id: organization.id)
         .by_actor(user)
         .since(days.days.ago)
         .recent
  end

  # Export audit trail as CSV
  def export_audit_trail_csv(days = 30)
    require "csv"
    events = Event.where(organization_id: organization.id)
                  .since(days.days.ago)
                  .recent

    CSV.generate do |csv|
      csv << [ "Timestamp", "User", "Event Type", "Details", "Changes" ]

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
