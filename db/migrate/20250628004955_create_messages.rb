# Find your existing CreateMessages migration and update it with these additions

class CreateMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :messages, id: :uuid do |t|
      t.references :chat, null: false, foreign_key: true, type: :uuid
      t.references :user, null: true, foreign_key: true, type: :uuid # Assistant messages don't have a user
      t.references :model, null: true, foreign_key: true, type: :bigint
      t.string :role, null: false
      t.text :content
      t.json :tool_calls, default: []
      t.json :tool_call_results, default: []
      t.json :context_snapshot, default: {}
      t.string :message_type, default: "text"
      t.json :metadata, default: {}
      t.string :llm_provider
      t.string :llm_model
      t.string :model_id_string
      t.string :tool_call_id
      t.integer :token_count
      t.integer :input_tokens
      t.integer :output_tokens
      t.decimal :processing_time, precision: 8, scale: 3

      t.timestamps
    end

    # Existing indexes
    add_index :messages, [ :chat_id, :created_at ]
    add_index :messages, [ :chat_id, :role, :created_at ]
    add_index :messages, [ :chat_id, :role ]
    add_index :messages, [ :chat_id, :tool_call_id ], where: "(tool_call_id IS NOT NULL)"
    add_index :messages, [ :llm_provider, :llm_model ]
    add_index :messages, :message_type
    add_index :messages, :model_id_string
    add_index :messages, :role
    add_index :messages, :tool_call_id
    add_index :messages, [ :user_id, :created_at ]

    # ADD: New constraints and indexes for tool call integrity
    # Add NOT NULL constraint to tool_call_id for messages with role 'tool'
    add_check_constraint :messages,
                        "role != 'tool' OR tool_call_id IS NOT NULL",
                        name: "tool_messages_must_have_tool_call_id"

    # Add index for better query performance on tool_call_id lookups
    add_index :messages, [ :role, :tool_call_id ],
              where: "role = 'tool' AND tool_call_id IS NOT NULL",
              name: "index_messages_on_role_and_tool_call_id"

    # Ensure tool_call_id uniqueness within a chat for tool messages
    add_index :messages, [ :chat_id, :tool_call_id ],
              unique: true,
              where: "role = 'tool' AND tool_call_id IS NOT NULL",
              name: "index_messages_unique_tool_call_id_per_chat"
  end
end
