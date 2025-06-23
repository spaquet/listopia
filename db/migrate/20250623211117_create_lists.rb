# db/migrate/20250623211117_create_lists.rb
class CreateLists < ActiveRecord::Migration[8.0]
  def change
    create_table :lists, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :title, null: false
      t.text :description
      t.integer :status, default: 0, null: false

      # Sharing settings
      t.boolean :is_public, default: false
      t.string :public_slug  # Remove the unique: true from here

      # Metadata
      t.json :metadata, default: {}
      t.string :color_theme, default: 'blue'

      t.timestamps
    end

    add_index :lists, :user_id
    add_index :lists, :status
    add_index :lists, :public_slug, unique: true  # Add unique constraint via index instead
    add_index :lists, :is_public
    add_index :lists, :created_at
  end
end
