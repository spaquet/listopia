class CreatePlanningRelationships < ActiveRecord::Migration[8.0]
  def change
    create_table :planning_relationships, id: :uuid do |t|
      t.uuid :planning_context_id, null: false, index: true
      t.string :parent_type, null: false
      t.string :child_type, null: false
      t.string :relationship_type, null: false
      t.integer :position, default: 0
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    # Indexes for common queries
    add_foreign_key :planning_relationships, :planning_contexts, column: :planning_context_id
    add_index :planning_relationships, [ :parent_type, :child_type ]
    add_index :planning_relationships, [ :relationship_type, :planning_context_id ]
  end
end
