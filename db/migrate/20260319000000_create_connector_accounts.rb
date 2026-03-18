class CreateConnectorAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :connector_accounts, id: :uuid do |t|
      t.uuid :user_id, null: false
      t.uuid :organization_id, null: false
      t.string :provider, null: false
      t.string :provider_uid, null: false
      t.string :display_name
      t.string :email
      t.text :access_token_encrypted
      t.text :refresh_token_encrypted
      t.timestamptz :token_expires_at
      t.string :token_scope
      t.string :status, default: "active", null: false
      t.timestamptz :last_sync_at
      t.text :last_error
      t.integer :error_count, default: 0, null: false
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :connector_accounts, [ :user_id, :provider, :provider_uid ], unique: true
    add_index :connector_accounts, :organization_id
    add_index :connector_accounts, :provider
    add_index :connector_accounts, :status
    add_index :connector_accounts, :user_id
    add_index :connector_accounts, :created_at

    add_foreign_key :connector_accounts, :users
    add_foreign_key :connector_accounts, :organizations
  end
end
