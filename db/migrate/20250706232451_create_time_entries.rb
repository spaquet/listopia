# db/migrate/20250706232451_create_time_entries.rb
class CreateTimeEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :time_entries, id: :uuid do |t|
      t.uuid :list_item_id, null: false
      t.uuid :user_id, null: false
      t.decimal :duration, precision: 10, scale: 2, default: 0.0, null: false
      t.datetime :started_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :ended_at
      t.text :notes
      t.json :metadata, default: {}

      t.timestamps
    end
  end
end
