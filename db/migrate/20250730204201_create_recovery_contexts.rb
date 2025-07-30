# db/migrate/20250730204201_create_recovery_contexts.rb
class CreateRecoveryContexts < ActiveRecord::Migration[8.0]
  def change
    create_table :recovery_contexts, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :chat, null: false, foreign_key: true, type: :uuid
      t.text :context_data # JSON data
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :recovery_contexts, :expires_at
    add_index :recovery_contexts, [:user_id, :chat_id]
    add_index :recovery_contexts, :created_at
  end
end
