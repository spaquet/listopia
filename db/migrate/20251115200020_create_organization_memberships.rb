class CreateOrganizationMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :organization_memberships, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.integer :role, default: 0, null: false
      t.integer :status, default: 1, null: false
      t.datetime :joined_at, null: false
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    # Unique constraint on organization and user
    add_index :organization_memberships, [ :organization_id, :user_id ], unique: true
    add_index :organization_memberships, :role
    add_index :organization_memberships, :status
    add_index :organization_memberships, :joined_at
  end
end
