class AddChatContextIdToChats < ActiveRecord::Migration[8.1]
  def change
    add_column :chats, :chat_context_id, :uuid, comment: "Reference to the chat context"
    add_foreign_key :chats, :chat_contexts, id: :id, column: :chat_context_id
    add_index :chats, :chat_context_id, unique: true
  end
end
