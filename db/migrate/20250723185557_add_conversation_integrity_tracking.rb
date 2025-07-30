# db/migrate/20250723185557_add_conversation_integrity_tracking.rb
class AddConversationIntegrityTracking < ActiveRecord::Migration[8.0]
  def change
    # Add conversation state tracking to chats table
    add_column :chats, :conversation_state, :string, default: "stable"
    add_column :chats, :last_cleanup_at, :datetime
    add_index :chats, :conversation_state

    # Add a composite index for better tool call lookup performance
    # (You already have tool_call_id index, this makes chat + tool_call_id lookups faster)
    add_index :messages, [ :chat_id, :tool_call_id ],
              where: "tool_call_id IS NOT NULL",
              name: "index_messages_on_chat_and_tool_call_id"
  end
end
