# rails generate migration CreateChats
class CreateChats < ActiveRecord::Migration[8.0]
  def change
    create_table :chats, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :title, limit: 255
      t.json :context, default: {}
      t.string :status, default: "active"
      t.datetime :last_message_at
      t.json :metadata, default: {}

      t.timestamps
    end

    add_index :chats, [ :user_id, :created_at ]
    add_index :chats, [ :user_id, :status ]
    add_index :chats, :last_message_at
  end
end
