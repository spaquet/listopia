class CreateToolCalls < ActiveRecord::Migration[8.1]
  def change
    create_table :tool_calls, id: :uuid do |t|
      t.string :tool_call_id, null: false
      t.string :name, null: false

      t.jsonb :arguments, default: {}

      t.timestamps
    end

    add_index :tool_calls, :tool_call_id, unique: true
    add_index :tool_calls, :name
  end
end
