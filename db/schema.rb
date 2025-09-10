# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_09_10_233319) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "active_storage_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.uuid "record_id", null: false
    t.uuid "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "board_columns", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "list_id", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["list_id"], name: "index_board_columns_on_list_id"
  end

  create_table "chats", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "title", limit: 255
    t.json "context", default: {}
    t.string "status", default: "active"
    t.datetime "last_message_at"
    t.json "metadata", default: {}
    t.string "model_id_string"
    t.datetime "last_stable_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "conversation_state", default: "stable"
    t.datetime "last_cleanup_at"
    t.bigint "model_id"
    t.index ["conversation_state"], name: "index_chats_on_conversation_state"
    t.index ["last_message_at"], name: "index_chats_on_last_message_at"
    t.index ["last_stable_at"], name: "index_chats_on_last_stable_at"
    t.index ["model_id"], name: "index_chats_on_model_id"
    t.index ["model_id_string"], name: "index_chats_on_model_id_string"
    t.index ["user_id", "created_at"], name: "index_chats_on_user_id_and_created_at"
    t.index ["user_id", "status"], name: "index_chats_on_user_id_and_status"
    t.index ["user_id"], name: "index_chats_on_user_id"
  end

  create_table "collaborators", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "collaboratable_type", null: false
    t.uuid "collaboratable_id", null: false
    t.uuid "user_id", null: false
    t.integer "permission", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["collaboratable_id", "collaboratable_type", "user_id"], name: "index_collaborators_on_collaboratable_and_user", unique: true
    t.index ["collaboratable_type", "collaboratable_id"], name: "index_collaborators_on_collaboratable"
    t.index ["user_id"], name: "index_collaborators_on_user_id"
  end

  create_table "comments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "commentable_type", null: false
    t.uuid "commentable_id", null: false
    t.uuid "user_id", null: false
    t.text "content", null: false
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["commentable_type", "commentable_id"], name: "index_comments_on_commentable"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "conversation_checkpoints", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "chat_id", null: false
    t.string "checkpoint_name", null: false
    t.integer "message_count", default: 0, null: false
    t.integer "tool_calls_count", default: 0, null: false
    t.string "conversation_state", default: "stable"
    t.text "messages_snapshot"
    t.text "context_data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_id", "checkpoint_name"], name: "index_conversation_checkpoints_on_chat_id_and_checkpoint_name", unique: true
    t.index ["chat_id"], name: "index_conversation_checkpoints_on_chat_id"
    t.index ["created_at"], name: "index_conversation_checkpoints_on_created_at"
  end

  create_table "conversation_contexts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.uuid "chat_id"
    t.string "action", limit: 50, null: false
    t.string "entity_type", limit: 50, null: false
    t.uuid "entity_id", null: false
    t.jsonb "entity_data", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "relevance_score", default: 100, null: false
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_id", "created_at"], name: "index_conversation_contexts_on_chat_id_and_created_at", order: { created_at: :desc }, where: "(chat_id IS NOT NULL)"
    t.index ["chat_id"], name: "index_conversation_contexts_on_chat_id"
    t.index ["entity_data"], name: "index_conversation_contexts_on_entity_data", using: :gin
    t.index ["expires_at"], name: "index_conversation_contexts_on_expires_at", where: "(expires_at IS NOT NULL)"
    t.index ["metadata"], name: "index_conversation_contexts_on_metadata", using: :gin
    t.index ["user_id", "action", "created_at"], name: "idx_on_user_id_action_created_at_a6d0f1b259", order: { created_at: :desc }
    t.index ["user_id", "created_at"], name: "index_conversation_contexts_on_user_id_and_created_at", order: { created_at: :desc }
    t.index ["user_id", "entity_type", "created_at"], name: "idx_on_user_id_entity_type_created_at_d22f14e09a", order: { created_at: :desc }
    t.index ["user_id", "entity_type", "entity_id", "created_at"], name: "idx_contexts_user_entity_time", order: { created_at: :desc }
    t.index ["user_id"], name: "index_conversation_contexts_on_user_id"
    t.check_constraint "action::text = ANY (ARRAY['list_viewed'::character varying, 'list_created'::character varying, 'list_updated'::character varying, 'list_deleted'::character varying, 'list_status_changed'::character varying, 'list_visibility_changed'::character varying, 'list_duplicated'::character varying, 'list_share_viewed'::character varying, 'list_ai_context_requested'::character varying, 'item_added'::character varying, 'item_updated'::character varying, 'item_completed'::character varying, 'item_deleted'::character varying, 'item_assigned'::character varying, 'item_uncompleted'::character varying, 'collaboration_added'::character varying, 'collaboration_removed'::character varying, 'chat_started'::character varying, 'chat_switched'::character varying, 'chat_message_sent'::character varying, 'chat_error'::character varying, 'page_visited'::character varying, 'dashboard_viewed'::character varying, 'lists_index_viewed'::character varying]::text[])", name: "valid_actions"
    t.check_constraint "entity_type::text = ANY (ARRAY['List'::character varying, 'ListItem'::character varying, 'User'::character varying, 'Chat'::character varying, 'Page'::character varying]::text[])", name: "valid_entity_types"
  end

  create_table "currents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "invitations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "invitable_type", null: false
    t.uuid "invitable_id", null: false
    t.uuid "user_id"
    t.string "email"
    t.string "invitation_token"
    t.datetime "invitation_sent_at"
    t.datetime "invitation_accepted_at"
    t.uuid "invited_by_id"
    t.integer "permission", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_invitations_on_email"
    t.index ["invitable_id", "invitable_type", "email"], name: "index_invitations_on_invitable_and_email", unique: true, where: "(email IS NOT NULL)"
    t.index ["invitable_id", "invitable_type", "user_id"], name: "index_invitations_on_invitable_and_user", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["invitable_type", "invitable_id"], name: "index_invitations_on_invitable"
    t.index ["invitation_token"], name: "index_invitations_on_invitation_token", unique: true
    t.index ["invited_by_id"], name: "index_invitations_on_invited_by_id"
    t.index ["user_id"], name: "index_invitations_on_user_id"
  end

  create_table "list_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "list_id", null: false
    t.uuid "assigned_user_id"
    t.string "title", null: false
    t.text "description"
    t.integer "item_type", default: 0, null: false
    t.integer "priority", default: 1, null: false
    t.boolean "completed", default: false
    t.datetime "completed_at"
    t.datetime "due_date"
    t.datetime "reminder_at"
    t.boolean "skip_notifications", default: false, null: false
    t.integer "position", default: 0
    t.decimal "estimated_duration", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "total_tracked_time", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "start_date", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.integer "duration_days", default: 0, null: false
    t.string "url"
    t.json "metadata", default: {}
    t.string "recurrence_rule", default: "none", null: false
    t.datetime "recurrence_end_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "board_column_id"
    t.index ["assigned_user_id", "completed"], name: "index_list_items_on_assigned_user_id_and_completed"
    t.index ["assigned_user_id"], name: "index_list_items_on_assigned_user_id"
    t.index ["board_column_id"], name: "index_list_items_on_board_column_id"
    t.index ["completed"], name: "index_list_items_on_completed"
    t.index ["created_at"], name: "index_list_items_on_created_at"
    t.index ["due_date", "completed"], name: "index_list_items_on_due_date_and_completed"
    t.index ["due_date"], name: "index_list_items_on_due_date"
    t.index ["item_type"], name: "index_list_items_on_item_type"
    t.index ["list_id", "completed"], name: "index_list_items_on_list_id_and_completed"
    t.index ["list_id", "position"], name: "index_list_items_on_list_id_and_position", unique: true
    t.index ["list_id", "priority"], name: "index_list_items_on_list_id_and_priority"
    t.index ["list_id"], name: "index_list_items_on_list_id"
    t.index ["position"], name: "index_list_items_on_position"
    t.index ["priority"], name: "index_list_items_on_priority"
    t.index ["skip_notifications"], name: "index_list_items_on_skip_notifications"
  end

  create_table "lists", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "title", null: false
    t.text "description"
    t.integer "status", default: 0, null: false
    t.boolean "is_public", default: false, null: false
    t.integer "public_permission", default: 0, null: false
    t.string "public_slug"
    t.integer "list_type", default: 0, null: false
    t.json "metadata", default: {}
    t.string "color_theme", default: "blue"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "list_items_count", default: 0, null: false
    t.integer "list_collaborations_count", default: 0, null: false
    t.index ["created_at"], name: "index_lists_on_created_at"
    t.index ["is_public"], name: "index_lists_on_is_public"
    t.index ["list_collaborations_count"], name: "index_lists_on_list_collaborations_count"
    t.index ["list_items_count"], name: "index_lists_on_list_items_count"
    t.index ["list_type"], name: "index_lists_on_list_type"
    t.index ["public_permission"], name: "index_lists_on_public_permission"
    t.index ["public_slug"], name: "index_lists_on_public_slug", unique: true
    t.index ["status"], name: "index_lists_on_status"
    t.index ["user_id", "created_at"], name: "index_lists_on_user_id_and_created_at"
    t.index ["user_id", "is_public"], name: "index_lists_on_user_is_public"
    t.index ["user_id", "list_type"], name: "index_lists_on_user_list_type"
    t.index ["user_id", "status", "list_type"], name: "index_lists_on_user_status_list_type"
    t.index ["user_id", "status"], name: "index_lists_on_user_id_and_status"
    t.index ["user_id", "status"], name: "index_lists_on_user_status"
    t.index ["user_id"], name: "index_lists_on_user_id"
  end

  create_table "messages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "chat_id", null: false
    t.uuid "user_id"
    t.string "role", null: false
    t.text "content"
    t.json "tool_calls", default: []
    t.json "tool_call_results", default: []
    t.json "context_snapshot", default: {}
    t.string "message_type", default: "text"
    t.json "metadata", default: {}
    t.string "llm_provider"
    t.string "llm_model"
    t.string "model_id_string"
    t.string "tool_call_id"
    t.integer "token_count"
    t.integer "input_tokens"
    t.integer "output_tokens"
    t.decimal "processing_time", precision: 8, scale: 3
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "model_id"
    t.index ["chat_id", "created_at"], name: "index_messages_on_chat_id_and_created_at"
    t.index ["chat_id", "role", "created_at"], name: "index_messages_on_chat_id_and_role_and_created_at"
    t.index ["chat_id", "role"], name: "index_messages_on_chat_id_and_role"
    t.index ["chat_id", "tool_call_id"], name: "index_messages_on_chat_and_tool_call_id", where: "(tool_call_id IS NOT NULL)"
    t.index ["chat_id"], name: "index_messages_on_chat_id"
    t.index ["llm_provider", "llm_model"], name: "index_messages_on_llm_provider_and_llm_model"
    t.index ["message_type"], name: "index_messages_on_message_type"
    t.index ["model_id"], name: "index_messages_on_model_id"
    t.index ["model_id_string"], name: "index_messages_on_model_id_string"
    t.index ["role"], name: "index_messages_on_role"
    t.index ["tool_call_id"], name: "index_messages_on_tool_call_id"
    t.index ["user_id", "created_at"], name: "index_messages_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_messages_on_user_id"
  end

  create_table "models", force: :cascade do |t|
    t.string "model_id", null: false
    t.string "name", null: false
    t.string "provider", null: false
    t.string "family"
    t.datetime "model_created_at"
    t.integer "context_window"
    t.integer "max_output_tokens"
    t.date "knowledge_cutoff"
    t.jsonb "modalities", default: {}
    t.jsonb "capabilities", default: []
    t.jsonb "pricing", default: {}
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["capabilities"], name: "index_models_on_capabilities", using: :gin
    t.index ["family"], name: "index_models_on_family"
    t.index ["modalities"], name: "index_models_on_modalities", using: :gin
    t.index ["provider", "model_id"], name: "index_models_on_provider_and_model_id", unique: true
    t.index ["provider"], name: "index_models_on_provider"
  end

  create_table "noticed_events", force: :cascade do |t|
    t.string "type"
    t.string "record_type"
    t.bigint "record_id"
    t.jsonb "params"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "notifications_count"
    t.index ["record_type", "record_id"], name: "index_noticed_events_on_record"
  end

  create_table "noticed_notifications", force: :cascade do |t|
    t.string "type"
    t.bigint "event_id", null: false
    t.string "recipient_type", null: false
    t.bigint "recipient_id", null: false
    t.datetime "read_at", precision: nil
    t.datetime "seen_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_noticed_notifications_on_event_id"
    t.index ["recipient_type", "recipient_id"], name: "index_noticed_notifications_on_recipient"
  end

  create_table "notification_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.boolean "email_notifications", default: true, null: false
    t.boolean "sms_notifications", default: false, null: false
    t.boolean "push_notifications", default: true, null: false
    t.boolean "collaboration_notifications", default: true, null: false
    t.boolean "list_activity_notifications", default: true, null: false
    t.boolean "item_activity_notifications", default: true, null: false
    t.boolean "status_change_notifications", default: true, null: false
    t.string "notification_frequency", default: "immediate", null: false
    t.time "quiet_hours_start"
    t.time "quiet_hours_end"
    t.string "timezone", default: "UTC"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["notification_frequency"], name: "index_notification_settings_on_notification_frequency"
    t.index ["user_id"], name: "index_notification_settings_on_user_id"
  end

  create_table "recovery_contexts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.uuid "chat_id", null: false
    t.text "context_data"
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_id"], name: "index_recovery_contexts_on_chat_id"
    t.index ["created_at"], name: "index_recovery_contexts_on_created_at"
    t.index ["expires_at"], name: "index_recovery_contexts_on_expires_at"
    t.index ["user_id", "chat_id"], name: "index_recovery_contexts_on_user_id_and_chat_id"
    t.index ["user_id"], name: "index_recovery_contexts_on_user_id"
  end

  create_table "relationships", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "parent_type", null: false
    t.uuid "parent_id", null: false
    t.string "child_type", null: false
    t.uuid "child_id", null: false
    t.integer "relationship_type", default: 0, null: false
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["child_type", "child_id"], name: "index_relationships_on_child"
    t.index ["parent_id", "parent_type", "child_id", "child_type"], name: "index_relationships_on_parent_and_child", unique: true
    t.index ["parent_type", "parent_id"], name: "index_relationships_on_parent"
  end

  create_table "roles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.string "resource_type"
    t.uuid "resource_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name", "resource_type", "resource_id"], name: "index_roles_on_name_and_resource_type_and_resource_id"
    t.index ["resource_type", "resource_id"], name: "index_roles_on_resource"
  end

  create_table "sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "session_token", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "last_accessed_at", default: -> { "CURRENT_TIMESTAMP" }
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_sessions_on_expires_at"
    t.index ["session_token"], name: "index_sessions_on_session_token", unique: true
    t.index ["user_id", "expires_at"], name: "index_sessions_on_user_id_and_expires_at"
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "taggings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "tag_id"
    t.string "taggable_type"
    t.uuid "taggable_id"
    t.string "tagger_type"
    t.uuid "tagger_id"
    t.string "context", limit: 128
    t.datetime "created_at", precision: nil
    t.string "tenant", limit: 128
    t.index ["context"], name: "index_taggings_on_context"
    t.index ["tag_id", "taggable_id", "taggable_type", "context", "tagger_id", "tagger_type"], name: "taggings_idx", unique: true
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
    t.index ["taggable_id", "taggable_type", "context"], name: "taggings_taggable_context_idx"
    t.index ["taggable_id", "taggable_type", "tagger_id", "context"], name: "taggings_idy"
    t.index ["taggable_id"], name: "index_taggings_on_taggable_id"
    t.index ["taggable_type", "taggable_id"], name: "index_taggings_on_taggable_type_and_taggable_id"
    t.index ["taggable_type"], name: "index_taggings_on_taggable_type"
    t.index ["tagger_id", "tagger_type"], name: "index_taggings_on_tagger_id_and_tagger_type"
    t.index ["tagger_id"], name: "index_taggings_on_tagger_id"
    t.index ["tagger_type", "tagger_id"], name: "index_taggings_on_tagger_type_and_tagger_id"
    t.index ["tenant"], name: "index_taggings_on_tenant"
  end

  create_table "tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "taggings_count", default: 0
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "time_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "list_item_id", null: false
    t.uuid "user_id", null: false
    t.decimal "duration", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "started_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "ended_at"
    t.text "notes"
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "tool_calls", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "message_id", null: false
    t.string "tool_call_id", null: false
    t.string "name", null: false
    t.jsonb "arguments", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "created_at"], name: "index_tool_calls_on_message_id_and_created_at"
    t.index ["message_id"], name: "index_tool_calls_on_message_id"
    t.index ["name"], name: "index_tool_calls_on_name"
    t.index ["tool_call_id"], name: "index_tool_calls_on_tool_call_id", unique: true
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "email", null: false
    t.string "name", null: false
    t.string "password_digest", null: false
    t.string "email_verification_token"
    t.datetime "email_verified_at"
    t.string "provider"
    t.string "uid"
    t.string "locale", limit: 10, default: "en", null: false
    t.string "timezone", limit: 50, default: "UTC", null: false
    t.string "avatar_url"
    t.text "bio"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["email_verification_token"], name: "index_users_on_email_verification_token", unique: true
    t.index ["locale"], name: "index_users_on_locale"
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["timezone"], name: "index_users_on_timezone"
  end

  create_table "users_roles", id: false, force: :cascade do |t|
    t.uuid "user_id"
    t.uuid "role_id"
    t.index ["role_id"], name: "index_users_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_users_roles_on_user_id_and_role_id"
    t.index ["user_id"], name: "index_users_roles_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "board_columns", "lists"
  add_foreign_key "chats", "models"
  add_foreign_key "chats", "users"
  add_foreign_key "collaborators", "users"
  add_foreign_key "comments", "users"
  add_foreign_key "conversation_checkpoints", "chats"
  add_foreign_key "conversation_contexts", "chats"
  add_foreign_key "conversation_contexts", "users"
  add_foreign_key "invitations", "users"
  add_foreign_key "invitations", "users", column: "invited_by_id"
  add_foreign_key "list_items", "board_columns"
  add_foreign_key "list_items", "lists"
  add_foreign_key "list_items", "users", column: "assigned_user_id"
  add_foreign_key "lists", "users"
  add_foreign_key "messages", "chats"
  add_foreign_key "messages", "models"
  add_foreign_key "messages", "users"
  add_foreign_key "notification_settings", "users"
  add_foreign_key "recovery_contexts", "chats"
  add_foreign_key "recovery_contexts", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "taggings", "tags"
  add_foreign_key "tool_calls", "messages"
end
