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
      # Add model_id for RubyLLM integration
      t.string :model_id
      # Add tool_call_id for linking tool result messages to tool calls
      t.string :tool_call_id
      t.integer :token_count
      # Add RubyLLM-specific token tracking
      t.integer :input_tokens
      t.integer :output_tokens
      t.decimal :processing_time, precision: 8, scale: 3

      t.timestamps
    end

    add_index :messages, [ :chat_id, :created_at ]
    add_index :messages, [ :chat_id, :role ]
    add_index :messages, [ :user_id, :created_at ]
    add_index :messages, :role
    add_index :messages, :message_type
    # Add indexes for RubyLLM performance
    add_index :messages, [:chat_id, :role, :created_at]
    add_index :messages, [:llm_provider, :llm_model]
    add_index :messages, :model_id
    add_index :messages, :tool_call_id
  end
end
