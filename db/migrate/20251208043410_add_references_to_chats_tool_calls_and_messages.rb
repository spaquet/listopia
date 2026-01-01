class AddReferencesToChatsToolCallsAndMessages < ActiveRecord::Migration[8.1]
  def change
    # chats.model_id -> models (bigint primary key)
    add_reference :chats, :model, foreign_key: true

    # tool_calls.message_id -> messages (uuid primary key)
    add_reference :tool_calls, :message, null: false, foreign_key: true, type: :uuid

    # messages.chat_id -> chats (uuid primary key)
    add_reference :messages, :chat, null: false, foreign_key: true, type: :uuid

    # messages.model_id -> models (bigint primary key)
    add_reference :messages, :model, foreign_key: true

    # messages.tool_call_id -> tool_calls (uuid primary key)
    add_reference :messages, :tool_call, foreign_key: true, type: :uuid
  end
end
