module Connectors
  # Base service for bidirectional sync operations
  class SyncService < BaseService
    def pull
      # Fetch data from external service and push to local system
      raise NotImplementedError, "Subclasses must implement #pull"
    end

    def push(data)
      # Push local data to external service
      raise NotImplementedError, "Subclasses must implement #push(data)"
    end

    protected

    # Create or update an event mapping
    def map_event(external_id:, external_type:, local_type:, local_id:, metadata: {})
      mapping = connector_account.event_mappings.find_or_initialize_by(
        external_id: external_id,
        external_type: external_type
      )

      mapping.update!(
        local_type: local_type,
        local_id: local_id,
        last_synced_at: Time.current,
        metadata: metadata
      )

      mapping
    end

    # Find a mapping by external ID
    def find_mapping(external_id, external_type)
      connector_account.event_mappings.find_by(
        external_id: external_id,
        external_type: external_type
      )
    end

    # Find all mappings of a given local type
    def find_mappings_by_local_type(local_type)
      connector_account.event_mappings.where(local_type: local_type)
    end
  end
end
