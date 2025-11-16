class CreateOrganizations < ActiveRecord::Migration[8.0]
  def change
    create_table :organizations, id: :uuid do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :size, default: 0, null: false
      t.integer :status, default: 0, null: false
      t.uuid :created_by_id, null: false
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    # Unique constraint on slug
    add_index :organizations, :slug, unique: true
    add_index :organizations, :created_by_id
    add_index :organizations, :status
    add_index :organizations, :size
    add_index :organizations, :created_at

    # Add foreign key for created_by
    add_foreign_key :organizations, :users, column: :created_by_id
  end
end
