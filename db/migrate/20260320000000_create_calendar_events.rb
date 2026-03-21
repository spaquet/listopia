class CreateCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :calendar_events, id: :uuid do |t|
      t.uuid :user_id, null: false
      t.uuid :organization_id, null: false
      t.uuid :connector_account_id

      t.string :external_event_id, null: false
      t.string :provider, null: false
      t.string :summary, null: false
      t.text :description
      t.timestamptz :start_time, null: false
      t.timestamptz :end_time
      t.string :status, default: "confirmed"
      t.string :timezone

      t.jsonb :attendees, default: [], null: false
      t.string :organizer_email
      t.string :organizer_name
      t.boolean :is_organizer, default: false

      # RAG search columns
      t.vector :embedding, limit: 1536
      t.datetime :embedding_generated_at
      t.boolean :requires_embedding_update, default: false, null: false

      t.timestamps
    end

    add_index :calendar_events, :user_id
    add_index :calendar_events, :organization_id
    add_index :calendar_events, :connector_account_id
    add_index :calendar_events, :external_event_id, unique: true
    add_index :calendar_events, [ :user_id, :start_time ]
    add_index :calendar_events, :attendees, using: :gin

    add_foreign_key :calendar_events, :users
    add_foreign_key :calendar_events, :organizations
    add_foreign_key :calendar_events, :connector_accounts, column: :connector_account_id
  end
end
