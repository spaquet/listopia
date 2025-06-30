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

ActiveRecord::Schema[8.0].define(version: 2025_06_30_212045) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "chats", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "title", limit: 255
    t.json "context", default: {}
    t.string "status", default: "active"
    t.datetime "last_message_at"
    t.json "metadata", default: {}
    t.string "model_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["last_message_at"], name: "index_chats_on_last_message_at"
    t.index ["model_id"], name: "index_chats_on_model_id"
    t.index ["user_id", "created_at"], name: "index_chats_on_user_id_and_created_at"
    t.index ["user_id", "status"], name: "index_chats_on_user_id_and_status"
    t.index ["user_id"], name: "index_chats_on_user_id"
  end

  create_table "currents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "list_collaborations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "list_id", null: false
    t.uuid "user_id"
    t.integer "permission", default: 0, null: false
    t.string "email"
    t.string "invitation_token"
    t.datetime "invitation_sent_at"
    t.datetime "invitation_accepted_at"
    t.uuid "invited_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_list_collaborations_on_email"
    t.index ["invitation_token"], name: "index_list_collaborations_on_invitation_token", unique: true
    t.index ["invited_by_id"], name: "index_list_collaborations_on_invited_by_id"
    t.index ["list_id", "email"], name: "index_list_collaborations_on_list_and_email", unique: true, where: "(email IS NOT NULL)"
    t.index ["list_id", "user_id"], name: "index_list_collaborations_on_list_and_user", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["list_id"], name: "index_list_collaborations_on_list_id"
    t.index ["permission"], name: "index_list_collaborations_on_permission"
    t.index ["user_id", "permission"], name: "index_list_collaborations_on_user_id_and_permission"
    t.index ["user_id"], name: "index_list_collaborations_on_user_id"
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
    t.integer "position", default: 0
    t.string "url"
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assigned_user_id", "completed"], name: "index_list_items_on_assigned_user_id_and_completed"
    t.index ["assigned_user_id"], name: "index_list_items_on_assigned_user_id"
    t.index ["completed"], name: "index_list_items_on_completed"
    t.index ["created_at"], name: "index_list_items_on_created_at"
    t.index ["due_date", "completed"], name: "index_list_items_on_due_date_and_completed"
    t.index ["due_date"], name: "index_list_items_on_due_date"
    t.index ["item_type"], name: "index_list_items_on_item_type"
    t.index ["list_id", "completed"], name: "index_list_items_on_list_id_and_completed"
    t.index ["list_id", "priority"], name: "index_list_items_on_list_id_and_priority"
    t.index ["list_id"], name: "index_list_items_on_list_id"
    t.index ["position"], name: "index_list_items_on_position"
    t.index ["priority"], name: "index_list_items_on_priority"
  end

  create_table "lists", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "title", null: false
    t.text "description"
    t.integer "status", default: 0, null: false
    t.boolean "is_public", default: false
    t.string "public_slug"
    t.json "metadata", default: {}
    t.string "color_theme", default: "blue"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_lists_on_created_at"
    t.index ["is_public"], name: "index_lists_on_is_public"
    t.index ["public_slug"], name: "index_lists_on_public_slug", unique: true
    t.index ["status"], name: "index_lists_on_status"
    t.index ["user_id", "created_at"], name: "index_lists_on_user_id_and_created_at"
    t.index ["user_id", "status"], name: "index_lists_on_user_id_and_status"
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
    t.string "model_id"
    t.string "tool_call_id"
    t.integer "token_count"
    t.integer "input_tokens"
    t.integer "output_tokens"
    t.decimal "processing_time", precision: 8, scale: 3
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_id", "created_at"], name: "index_messages_on_chat_id_and_created_at"
    t.index ["chat_id", "role", "created_at"], name: "index_messages_on_chat_id_and_role_and_created_at"
    t.index ["chat_id", "role"], name: "index_messages_on_chat_id_and_role"
    t.index ["chat_id"], name: "index_messages_on_chat_id"
    t.index ["llm_provider", "llm_model"], name: "index_messages_on_llm_provider_and_llm_model"
    t.index ["message_type"], name: "index_messages_on_message_type"
    t.index ["model_id"], name: "index_messages_on_model_id"
    t.index ["role"], name: "index_messages_on_role"
    t.index ["tool_call_id"], name: "index_messages_on_tool_call_id"
    t.index ["user_id", "created_at"], name: "index_messages_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_messages_on_user_id"
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
    t.string "avatar_url"
    t.text "bio"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["email_verification_token"], name: "index_users_on_email_verification_token", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
  end

  add_foreign_key "chats", "users"
  add_foreign_key "list_collaborations", "lists"
  add_foreign_key "list_collaborations", "users"
  add_foreign_key "list_collaborations", "users", column: "invited_by_id"
  add_foreign_key "list_items", "lists"
  add_foreign_key "list_items", "users", column: "assigned_user_id"
  add_foreign_key "lists", "users"
  add_foreign_key "messages", "chats"
  add_foreign_key "messages", "users"
  add_foreign_key "notification_settings", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "tool_calls", "messages"
end
