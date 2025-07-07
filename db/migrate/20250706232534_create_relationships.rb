# db/migrate/20250706232534_create_relationships.rb
class CreateRelationships < ActiveRecord::Migration[8.0]
  def change
    create_table :relationships, id: :uuid do |t|
      t.references :parent, polymorphic: true, null: false, type: :uuid, index: true
      t.references :child, polymorphic: true, null: false, type: :uuid, index: true
      t.integer :relationship_type, null: false, default: 0
      t.json :metadata, default: {}

      t.timestamps
    end

    add_index :relationships, [ :parent_id, :parent_type, :child_id, :child_type ], unique: true, name: 'index_relationships_on_parent_and_child'
  end
end
