module Connectors
  # == Schema Information
  #
  # Table name: connector_event_mappings
  #
  #  id                   :uuid             not null, primary key
  #  external_etag        :string
  #  external_type        :string           not null
  #  last_synced_at       :timestamptz
  #  local_type           :string           not null
  #  metadata             :jsonb            not null
  #  sync_direction       :string           default("both"), not null
  #  created_at           :datetime         not null
  #  updated_at           :datetime         not null
  #  connector_account_id :uuid             not null
  #  external_id          :string           not null
  #  local_id             :uuid
  #
  # Indexes
  #
  #  idx_on_connector_account_id_external_id_external_ty_53f2784fcd  (connector_account_id,external_id,external_type) UNIQUE
  #  index_connector_event_mappings_on_created_at                    (created_at)
  #  index_connector_event_mappings_on_local_id                      (local_id)
  #  index_connector_event_mappings_on_local_type                    (local_type)
  #
  # Foreign Keys
  #
  #  fk_rails_...  (connector_account_id => connector_accounts.id)
  #
  class EventMapping < ApplicationRecord
    self.table_name = "connector_event_mappings"

    belongs_to :account, class_name: "Connectors::Account", foreign_key: :connector_account_id

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
