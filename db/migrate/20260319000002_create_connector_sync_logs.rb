class CreateConnectorSyncLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :connector_sync_logs, id: :uuid do |t|
      t.uuid :connector_account_id, null: false
      t.string :operation, null: false
      t.string :status, null: false
      t.integer :records_processed, default: 0
      t.integer :records_created, default: 0
      t.integer :records_updated, default: 0
      t.integer :records_failed, default: 0
      t.text :error_message
      t.integer :duration_ms
      t.timestamptz :started_at
      t.timestamptz :completed_at

      t.timestamps
    end

    add_index :connector_sync_logs, :connector_account_id
    add_index :connector_sync_logs, :operation
    add_index :connector_sync_logs, :status
    add_index :connector_sync_logs, :created_at
    add_foreign_key :connector_sync_logs, :connector_accounts
  end
end
