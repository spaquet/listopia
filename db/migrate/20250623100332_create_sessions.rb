# db/migrate/20
class CreateSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :sessions, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :session_token, null: false
      t.string :ip_address
      t.string :user_agent
      t.datetime :last_accessed_at, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :sessions, :session_token, unique: true
    add_index :sessions, :expires_at
    add_index :sessions, [ :user_id, :expires_at ]
  end
end
