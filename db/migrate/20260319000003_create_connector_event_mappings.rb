class CreateConnectorEventMappings < ActiveRecord::Migration[8.0]
  def change
    create_table :connector_event_mappings, id: :uuid do |t|
      t.uuid :connector_account_id, null: false
      t.string :external_id, null: false
      t.string :external_type, null: false
      t.string :local_type, null: false
      t.uuid :local_id
      t.string :sync_direction, default: "both", null: false
      t.timestamptz :last_synced_at
      t.string :external_etag
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :connector_event_mappings, [ :connector_account_id, :external_id, :external_type ], unique: true
    add_index :connector_event_mappings, :local_id
    add_index :connector_event_mappings, :local_type
    add_index :connector_event_mappings, :created_at
    add_foreign_key :connector_event_mappings, :connector_accounts
  end
end
