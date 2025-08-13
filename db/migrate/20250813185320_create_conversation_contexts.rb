# db/migrate/20250813185320_create_conversation_contexts.rb
class CreateConversationContexts < ActiveRecord::Migration[8.0]
  def change

    create_table :conversation_contexts, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :chat, null: true, foreign_key: true, type: :uuid

      # Action tracking
      t.string :action, null: false, limit: 50
      t.string :entity_type, null: false, limit: 50
      t.uuid :entity_id, null: false

      # Flexible metadata storage using JSONB
      t.jsonb :entity_data, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      # Context priority and relevance
      t.integer :relevance_score, null: false, default: 100
      t.datetime :expires_at

      t.timestamps
    end

    # Optimized indexes for context resolution queries
    add_index :conversation_contexts, [ :user_id, :created_at ], order: { created_at: :desc }
    add_index :conversation_contexts, [ :user_id, :action, :created_at ], order: { created_at: :desc }
    add_index :conversation_contexts, [ :user_id, :entity_type, :created_at ], order: { created_at: :desc }
    add_index :conversation_contexts, [ :chat_id, :created_at ], where: "chat_id IS NOT NULL", order: { created_at: :desc }

    # JSONB indexes for efficient entity data queries
    add_index :conversation_contexts, :entity_data, using: :gin
    add_index :conversation_contexts, :metadata, using: :gin

    # Composite index for complex queries
    add_index :conversation_contexts, [ :user_id, :entity_type, :entity_id, :created_at ],
              name: "idx_contexts_user_entity_time", order: { created_at: :desc }

    # Cleanup index for expired contexts
    add_index :conversation_contexts, :expires_at, where: "expires_at IS NOT NULL"

    # Check constraint for valid actions
    add_check_constraint :conversation_contexts,
                    "action IN ('list_viewed', 'list_created', 'list_updated', 'list_deleted', 'list_status_changed', 'list_visibility_changed', 'list_duplicated', 'list_share_viewed', 'list_ai_context_requested', 'item_added', 'item_updated', 'item_completed', 'item_deleted', 'item_assigned', 'item_uncompleted', 'collaboration_added', 'collaboration_removed', 'chat_started', 'chat_switched', 'chat_message_sent', 'chat_error', 'page_visited', 'dashboard_viewed', 'lists_index_viewed')",
                    name: "valid_actions"

    # Check constraint for valid entity types
    add_check_constraint :conversation_contexts,
                    "entity_type IN ('List', 'ListItem', 'User', 'Chat', 'Page')",
                    name: "valid_entity_types"
  end
end
