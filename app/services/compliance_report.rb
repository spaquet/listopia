# Generates compliance reports from Event audit trail
# Tracks who changed what, when, with full context
#
# Usage:
#   report = ComplianceReport.new(organization, events, options)
#   report.sensitive_changes        # => Changes to critical fields
#   report.user_activity            # => What each user did
#   report.to_csv                   # => Export as CSV

class ComplianceReport
  SENSITIVE_FIELDS = %w[status priority assigned_user_id access is_public owner_id].freeze
  CRITICAL_ACTIONS = %w[deleted completed assigned].freeze

  attr_reader :organization, :events, :options

  def initialize(organization, events, options = {})
    @organization = organization
    @events = events.is_a?(ActiveRecord::Relation) ? events.to_a : events
    @options = {
      include_sensitive: true,
      include_critical: true,
      min_changes: 0
    }.merge(options)
  end

  # Sensitive field changes (access control, ownership, status)
  def sensitive_changes
    @sensitive_changes ||= events.select do |event|
      next unless event.event_data["changes"].is_a?(Hash)

      event.event_data["changes"].keys.any? { |k| k.in?(SENSITIVE_FIELDS) }
    end
  end

  # Critical actions (deletions, completions, assignments)
  def critical_actions
    @critical_actions ||= events.select do |event|
      CRITICAL_ACTIONS.any? { |action| event.event_type.include?(action) }
    end
  end

  # Changes grouped by user
  def changes_by_user
    @changes_by_user ||= events.group_by do |event|
      event.actor&.email || "System"
    end.transform_values { |es| es.sort_by { |e| e.created_at }.reverse }
  end

  # Users with most changes
  def most_active_users(limit = 10)
    changes_by_user.map { |user, changes| { user:, count: changes.size } }
                   .sort_by { |h| h[:count] }
                   .reverse
                   .first(limit)
  end

  # Changes to specific item/list
  def changes_to_resource(resource_id)
    events.select do |event|
      event.event_data["item_id"] == resource_id ||
        event.event_data["list_id"] == resource_id
    end
  end

  # Timeline of changes
  def timeline
    @timeline ||= events.sort_by(&:created_at).reverse
  end

  # Summary statistics
  def summary
    {
      total_events: events.count,
      sensitive_changes: sensitive_changes.count,
      critical_actions: critical_actions.count,
      unique_users: changes_by_user.keys.count,
      date_range: {
        start: events.map(&:created_at).min,
        end: events.map(&:created_at).max
      },
      most_active_users: most_active_users(5)
    }
  end

  # Risk assessment
  def risk_assessment
    {
      high_risk: {
        bulk_deletions: bulk_deletions?,
        access_changes: access_change_count,
        ownership_changes: ownership_change_count
      },
      anomalies: detect_anomalies
    }
  end

  # Export as CSV
  def to_csv
    require "csv"
    CSV.generate do |csv|
      csv << [ "Timestamp", "User", "Action", "Resource Type", "Resource ID", "Details", "Sensitive", "Risk Level" ]

      events.each do |event|
        is_sensitive = sensitive_changes.include?(event)
        is_critical = critical_actions.include?(event)

        csv << [
          event.created_at.to_s,
          event.actor&.email || "System",
          event.event_type,
          extract_resource_type(event),
          extract_resource_id(event),
          format_event_details(event),
          is_sensitive ? "YES" : "NO",
          calculate_risk_level(event, is_sensitive, is_critical)
        ]
      end
    end
  end

  # Export as JSON for APIs
  def to_json
    {
      organization: {
        id: organization.id,
        name: organization.name
      },
      report_date: Time.current,
      period: {
        start: events.map(&:created_at).min,
        end: events.map(&:created_at).max
      },
      summary: summary,
      risk_assessment: risk_assessment,
      sensitive_changes: sensitive_changes.map(&:as_json),
      critical_actions: critical_actions.map(&:as_json),
      changes_by_user: changes_by_user.transform_values { |es| es.map(&:as_json) }
    }.to_json
  end

  # Generate HTML report (for views)
  def to_html
    {
      summary: summary,
      risk_assessment: risk_assessment,
      sensitive_changes: format_changes_table(sensitive_changes),
      critical_actions: format_changes_table(critical_actions),
      top_users: most_active_users(10),
      timeline: timeline.first(50)
    }
  end

  private

  def bulk_deletions?
    deletion_count = events.count { |e| e.event_type.include?("deleted") }
    deletion_count > 10  # Threshold for "bulk"
  end

  def access_change_count
    events.count do |event|
      next unless event.event_data["changes"].is_a?(Hash)

      event.event_data["changes"].keys.any? { |k| k.in?(%w[is_public access owner_id]) }
    end
  end

  def ownership_change_count
    events.count do |event|
      next unless event.event_data["changes"].is_a?(Hash)

      event.event_data["changes"].key?("user_id") ||
        event.event_data["changes"].key?("owner_id")
    end
  end

  def detect_anomalies
    anomalies = []

    # Same user making too many changes in short period
    changes_by_user.each do |user, changes|
      if changes.count > 100 && changes.first(5).all? { |e| (changes.first.created_at - e.created_at).abs < 5.minutes }
        anomalies << "High volume changes by #{user} in short period"
      end
    end

    # Rapid deletions
    deletions = events.select { |e| e.event_type.include?("deleted") }
    if deletions.count > 5 && (deletions.first.created_at - deletions.last.created_at).abs < 1.hour
      anomalies << "Rapid deletions detected (#{deletions.count} in 1 hour)"
    end

    anomalies
  end

  def extract_resource_type(event)
    event.event_type.split(".").first.titleize
  end

  def extract_resource_id(event)
    event.event_data["item_id"] || event.event_data["list_id"] || event.event_data["id"]
  end

  def format_event_details(event)
    case event.event_type
    when "list_item.created"
      "Created: #{event.event_data['title']}"
    when "list_item.deleted"
      "Deleted: #{event.event_data['title']}"
    when "list_item.assigned"
      "Assigned to user"
    when "list_item.status_changed"
      "#{event.event_data['from']} → #{event.event_data['to']}"
    else
      event.event_type
    end
  end

  def calculate_risk_level(event, is_sensitive, is_critical)
    return "CRITICAL" if is_critical && is_sensitive
    return "HIGH" if is_sensitive
    return "MEDIUM" if is_critical
    "LOW"
  end

  def format_changes_table(events_list)
    events_list.map do |event|
      {
        timestamp: event.created_at,
        actor: event.actor&.email || "System",
        type: event.event_type,
        details: format_event_details(event)
      }
    end
  end
end
