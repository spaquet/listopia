# db/migrate/20250623211117_create_lists.rb
class CreateLists < ActiveRecord::Migration[8.0]
  def change
    create_table :lists, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid, index: true
      t.string :title, null: false
      t.text :description
      t.integer :status, default: 0, null: false

      # Sharing settings
      t.boolean :is_public, default: false
      t.string :public_slug

      # List type (personal, professional)
      t.integer :list_type, default: 0, null: false

      # Metadata
      t.json :metadata, default: {}
      t.string :color_theme, default: 'blue'

      t.timestamps
    end

    # Only add indexes that aren't automatically created by t.references
    add_index :lists, :status
    add_index :lists, :public_slug, unique: true
    add_index :lists, :is_public
    add_index :lists, :created_at
    add_index :lists, :list_type
    add_index :lists, [ :user_id, :status, :list_type ], name: "index_lists_on_user_status_list_type"
    add_index :lists, [ :user_id, :is_public ], name: "index_lists_on_user_is_public"
    add_index :lists, [ :user_id, :status ], name: "index_lists_on_user_status"
    add_index :lists, [ :user_id, :list_type ], name: "index_lists_on_user_list_type"
  end
end
