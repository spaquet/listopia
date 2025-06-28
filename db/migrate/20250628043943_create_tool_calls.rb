# db/migrate/20250628043943_create_tool_calls.rb
class CreateToolCalls < ActiveRecord::Migration[8.0]
  def change
    create_table :tool_calls, id: :uuid do |t|
      t.references :message, null: false, foreign_key: true, type: :uuid # Assistant message making the call
      t.string :tool_call_id, null: false # Provider's ID for the call
      t.string :name, null: false
      t.jsonb :arguments, default: {} # Use jsonb for PostgreSQL

      t.timestamps
    end

    add_index :tool_calls, :tool_call_id, unique: true
    add_index :tool_calls, [ :message_id, :created_at ]
    add_index :tool_calls, :name
  end
end
