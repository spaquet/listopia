class CreatePlanningRelationships < ActiveRecord::Migration[8.1]
  def change
    create_table :planning_relationships, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :chat_context_id, null: false, comment: "Reference to the planning context"
      t.string :parent_type, null: false, comment: "Type of parent item"
      t.string :child_type, null: false, comment: "Type of child item"
      t.string :relationship_type, null: false, comment: "Type of relationship (hierarchy, dependency, etc.)"
      t.jsonb :metadata, default: {}, comment: "Additional relationship metadata"

      t.timestamps
    end

    # Indexes
    add_index :planning_relationships, :chat_context_id
    add_index :planning_relationships, [:chat_context_id, :relationship_type]

    # Foreign key
    add_foreign_key :planning_relationships, :chat_contexts, id: :id
  end
end
