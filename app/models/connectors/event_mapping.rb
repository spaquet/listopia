module Connectors
  # == Schema Information
  #
  # Table name: connector_event_mappings
  #
  #  id                     :uuid
  #  connector_account_id   :uuid
  #  external_id            :string
  #  external_type          :string
  #  local_type             :string
  #  local_id               :uuid
  #  sync_direction         :string
  #  last_synced_at         :timestamptz
  #  external_etag          :string
  #  metadata               :jsonb
  #  created_at             :timestamptz
  #  updated_at             :timestamptz
  #
  class EventMapping < ApplicationRecord
    self.table_name = "connector_event_mappings"

    belongs_to :account, class_name: "Connectors::Account"

    validates :external_id, :external_type, :local_type, presence: true
    validates :external_id, uniqueness: { scope: [ :connector_account_id, :external_type ] }
    validates :sync_direction, inclusion: { in: %w[push pull both] }

    enum :sync_direction, { push: "push", pull: "pull", both: "both" }

    scope :by_type, ->(local_type) { where(local_type: local_type) }
    scope :by_external_type, ->(external_type) { where(external_type: external_type) }
    scope :with_local_id, ->(local_id) { where(local_id: local_id) }
    scope :recent, -> { order(created_at: :desc) }
  end
end
