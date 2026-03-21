class CreateConnectorWebhookSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :connector_webhook_subscriptions, id: :uuid do |t|
      t.uuid :connector_account_id, null: false
      t.string :provider, null: false
      t.string :calendar_id, null: false
      t.string :subscription_id, null: false
      t.string :resource_id
      t.string :channel_token
      t.timestamptz :expires_at
      t.string :status, default: "active"

      t.timestamps
    end

    add_foreign_key :connector_webhook_subscriptions, :connector_accounts, column: :connector_account_id
    add_index :connector_webhook_subscriptions, :subscription_id, unique: true
    add_index :connector_webhook_subscriptions, [ :connector_account_id, :status ]
    add_index :connector_webhook_subscriptions, :expires_at
  end
end
