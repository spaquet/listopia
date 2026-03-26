class RemoveChatContext < ActiveRecord::Migration[8.1]
  def change
    remove_column :chats, :chat_context_id, :uuid
    drop_table :chat_contexts
  end
end
