class CreateTeamMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :team_memberships, id: :uuid do |t|
      t.references :team, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :organization_membership, type: :uuid, null: false, foreign_key: true
      t.integer :role, default: 0, null: false
      t.datetime :joined_at, null: false
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    # Unique constraint on team and user
    add_index :team_memberships, [ :team_id, :user_id ], unique: true
    add_index :team_memberships, :role
    add_index :team_memberships, :joined_at
  end
end
