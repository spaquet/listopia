# Combines Logidze version history with Event actor tracking
# Provides a unified audit trail showing who changed what when
#
# Usage:
#   audit = AuditTrail.new(list_item, organization_id)
#   audit.entries  # => array of {timestamp, actor, changes}
#   audit.versions # => Logidze snapshots with actor info

class AuditTrail
  attr_reader :resource, :organization_id

  def initialize(resource, organization_id)
    @resource = resource
    @organization_id = organization_id
  end

  # Unified audit entries combining Logidze + Events
  def entries
    @entries ||= build_unified_entries
  end

  # Get all Logidze versions (full snapshots)
  def versions
    return [] unless resource.respond_to?(:logidze_versions)

    resource.logidze_versions.map do |version|
      {
        version: version.version,
        timestamp: version.timestamp,
        changes: version.changes,
        actor: find_actor_for_version(version),
        actor_id: find_actor_id_for_version(version)
      }
    end
  end

  # Get change events for this resource
  def change_events
    Event.where(organization_id:)
         .where("event_data->>'item_id' = ? OR event_data->>'list_id' = ?",
                resource.id, resource.id)
         .recent
  end

  # Get who changed what
  def changes_by_field
    versions.each_with_object({}) do |version, acc|
      version[:changes]&.each do |field, (old_val, new_val)|
        acc[field] ||= []
        acc[field] << {
          timestamp: version[:timestamp],
          actor: version[:actor],
          from: old_val,
          to: new_val
        }
      end
    end
  end

  # Get change history for specific field
  def field_history(field_name)
    changes_by_field[field_name] || []
  end

  # Timeline of all changes
  def timeline
    entries.sort_by { |e| e[:timestamp] }.reverse
  end

  # Export as JSON for APIs
  def to_json
    {
      resource: {
        type: resource.class.name,
        id: resource.id
      },
      entries: entries,
      summary: build_summary
    }.to_json
  end

  private

  def build_unified_entries
    return [] unless resource.respond_to?(:logidze_versions)

    versions.map do |version|
      {
        timestamp: version[:timestamp],
        actor: version[:actor],
        actor_id: version[:actor_id],
        version: version[:version],
        changes: version[:changes],
        event_record: find_matching_event(version)
      }
    end
  end

  def find_actor_for_version(version)
    event = find_matching_event(version)
    event&.actor&.email || "Unknown"
  end

  def find_actor_id_for_version(version)
    event = find_matching_event(version)
    event&.actor_id
  end

  def find_matching_event(version)
    # Match event to Logidze version by timestamp (within 1 second)
    change_events.find do |event|
      (event.created_at.to_i - version[:timestamp].to_i).abs <= 1
    end
  end

  def build_summary
    {
      total_versions: versions.count,
      unique_actors: versions.map { |v| v[:actor] }.uniq.compact.count,
      first_change: versions.last&.dig(:timestamp),
      last_change: versions.first&.dig(:timestamp),
      fields_changed: changes_by_field.keys.sort
    }
  end
end
