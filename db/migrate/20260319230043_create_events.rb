class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events, id: :uuid do |t|
      t.string :event_type, null: false
      t.references :actor, foreign_key: { to_table: :users }, type: :uuid
      t.jsonb :event_data, default: {}
      t.references :organization, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end

    add_index :events, :event_type
    add_index :events, [ :organization_id, :created_at ]
    add_index :events, [ :actor_id, :created_at ]
  end
end
