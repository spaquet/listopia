class CreatePlanningContexts < ActiveRecord::Migration[8.0]
  def change
    create_table :planning_contexts, id: :uuid do |t|
      t.uuid :user_id, null: false, index: true
      t.uuid :chat_id, null: false, index: { unique: true }
      t.uuid :organization_id, null: false, index: true

      # State and status tracking
      t.string :state, default: "initial", null: false, index: true
      t.string :status, default: "pending", null: false
      t.string :error_message, limit: 500

      # Core planning information
      t.text :request_content, comment: "Original user request"
      t.string :detected_intent, index: true
      t.decimal :intent_confidence, precision: 3, scale: 2
      t.string :planning_domain, index: true
      t.string :complexity_level
      t.text :complexity_reasoning
      t.boolean :is_complex, default: false

      # Requirements analysis
      t.jsonb :parent_requirements, default: {}
      t.jsonb :child_requirements, default: {}
      t.jsonb :item_generation_strategy, default: {}

      # Extracted parameters
      t.jsonb :parameters, default: {}
      t.string :missing_parameters, array: true, default: []

      # Pre-creation planning
      t.jsonb :pre_creation_questions, array: true, default: []
      t.jsonb :pre_creation_answers, default: {}

      # Generated items
      t.jsonb :generated_items, array: true, default: []
      t.jsonb :hierarchical_items, default: {}

      # Reference to created list
      t.uuid :list_created_id

      # Extended metadata (thinking tokens, generation time, etc.)
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    # Indexes for common queries
    add_index :planning_contexts, [ :user_id, :created_at ]
    add_index :planning_contexts, [ :state, :status ]
    add_index :planning_contexts, [ :detected_intent, :created_at ]
  end
end
