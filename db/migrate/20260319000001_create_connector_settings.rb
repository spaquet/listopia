class CreateConnectorSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :connector_settings, id: :uuid do |t|
      t.uuid :connector_account_id, null: false
      t.string :key, null: false
      t.text :value

      t.timestamps
    end

    add_index :connector_settings, [ :connector_account_id, :key ], unique: true
    add_foreign_key :connector_settings, :connector_accounts
  end
end
