class CreateChatContexts < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_contexts, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      # Associations
      t.uuid :user_id, null: false
      t.uuid :chat_id, null: false
      t.uuid :organization_id, null: false

      # State machine
      t.string :state, null: false, default: "initial", comment: "State: initial, pre_creation, resource_creation, completed"
      t.string :status, null: false, default: "pending", comment: "Status: pending, analyzing, awaiting_user_input, processing, complete, error"

      # Request semantics
      t.text :request_content, comment: "Original user request"
      t.string :detected_intent, comment: "Detected intent: create_list, navigate_to_page, etc."
      t.string :planning_domain, comment: "Domain: vacation, sprint, roadshow, etc."
      t.boolean :is_complex, default: false, comment: "Whether request is complex and needs clarifying questions"
      t.string :complexity_level, comment: "simple, complex"
      t.text :complexity_reasoning, comment: "Why the request was classified as simple or complex"

      # Planning data
      t.jsonb :parameters, default: {}, comment: "Extracted parameters from request"
      t.jsonb :pre_creation_questions, default: [], comment: "Clarifying questions for complex lists"
      t.jsonb :pre_creation_answers, default: {}, comment: "User's answers to pre-creation questions"
      t.jsonb :hierarchical_items, default: {}, comment: "Parent items, subdivisions, subdivision type for nested lists"
      t.jsonb :generated_items, default: [], comment: "Generated items"
      t.string :missing_parameters, array: true, default: [], comment: "Parameters missing from request"

      # List creation tracking
      t.uuid :list_created_id, comment: "ID of the created list"

      # Context reuse after creation
      t.boolean :post_creation_mode, default: false, comment: "True when showing 'keep or clear context' buttons after list creation"

      # Crash recovery
      t.datetime :last_activity_at, comment: "Timestamp of last interaction; used for connection recovery"
      t.jsonb :recovery_checkpoint, default: {}, comment: "Last known good state snapshot for crash recovery"

      # Metadata & error handling
      t.jsonb :metadata, default: {}, comment: "Additional metadata and performance metrics (thinking_tokens, generation_time_ms, etc.)"
      t.text :error_message, comment: "Error message if status is error"

      # Timestamps
      t.timestamps
    end

    # Indexes
    add_index :chat_contexts, :user_id
    add_index :chat_contexts, :chat_id, unique: true
    add_index :chat_contexts, :organization_id
    add_index :chat_contexts, :state
    add_index :chat_contexts, :status
    add_index :chat_contexts, :post_creation_mode
    add_index :chat_contexts, :last_activity_at

    # Foreign keys
    add_foreign_key :chat_contexts, :users, id: :id
    add_foreign_key :chat_contexts, :chats, id: :id
    add_foreign_key :chat_contexts, :organizations, id: :id
  end
end
