# db/migrate/20250628004955_create_messages.rb
class CreateMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :messages, id: :uuid do |t|
      t.references :chat, null: false, foreign_key: true, type: :uuid
      t.references :user, null: true, foreign_key: true, type: :uuid # null for assistant messages
      t.string :role, null: false # 'user', 'assistant', 'system', 'tool'
      t.text :content
      t.json :tool_calls, default: []
      t.json :tool_call_results, default: []
      t.json :context_snapshot, default: {}
      t.string :message_type, default: "text" # 'text', 'tool_call', 'tool_result'
      t.json :metadata, default: {}
      t.string :llm_provider
      t.string :llm_model
      t.integer :token_count
      t.decimal :processing_time, precision: 8, scale: 3

      t.timestamps
    end

    add_index :messages, [ :chat_id, :created_at ]
    add_index :messages, [ :chat_id, :role ]
    add_index :messages, [ :user_id, :created_at ]
    add_index :messages, :role
    add_index :messages, :message_type
  end
end
