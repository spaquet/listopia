# db/migrate/20250730204143_create_conversation_checkpoints.rb
class CreateConversationCheckpoints < ActiveRecord::Migration[8.0]
  def change
    create_table :conversation_checkpoints, id: :uuid do |t|
      t.references :chat, null: false, foreign_key: true, type: :uuid
      t.string :checkpoint_name, null: false
      t.integer :message_count, null: false, default: 0
      t.integer :tool_calls_count, null: false, default: 0
      t.string :conversation_state, default: "stable"
      t.text :messages_snapshot # JSON data
      t.text :context_data # JSON data

      t.timestamps
    end

    add_index :conversation_checkpoints, [ :chat_id, :checkpoint_name ], unique: true
    add_index :conversation_checkpoints, :created_at
  end
end
