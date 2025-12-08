class AddTemplateSupportToMessages < ActiveRecord::Migration[8.1]
  def change
    # Note: metadata column already exists from RubyLLM integration
    # Only add columns that don't exist yet
    add_column :messages, :template_type, :string, if_not_exists: true
    add_column :messages, :chat_id, :uuid, if_not_exists: true
    add_column :messages, :user_id, :uuid, if_not_exists: true

    add_index :messages, :template_type, if_not_exists: true
    add_index :messages, :chat_id, if_not_exists: true
    add_index :messages, :user_id, if_not_exists: true
    add_index :messages, [:chat_id, :created_at], if_not_exists: true

    add_foreign_key :messages, :chats, if_not_exists: true
    add_foreign_key :messages, :users, if_not_exists: true
  end
end
