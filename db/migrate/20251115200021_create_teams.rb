class CreateTeams < ActiveRecord::Migration[8.0]
  def change
    create_table :teams, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.uuid :created_by_id, null: false
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    # Unique constraint on organization and slug
    add_index :teams, [:organization_id, :slug], unique: true
    add_index :teams, :created_by_id
    add_index :teams, :created_at

    # Add foreign key for created_by
    add_foreign_key :teams, :users, column: :created_by_id
  end
end
