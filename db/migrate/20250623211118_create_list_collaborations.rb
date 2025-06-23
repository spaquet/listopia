# db/migrate/20250623211118_create_list_collaborations.rb
class CreateListCollaborations < ActiveRecord::Migration[8.0]
  def change
    create_table :list_collaborations, id: :uuid do |t|
      t.references :list, null: false, foreign_key: true, type: :uuid
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.integer :permission, default: 0, null: false

      # Invitation details
      t.string :invitation_token
      t.datetime :invitation_sent_at
      t.datetime :invitation_accepted_at
      t.references :invited_by, foreign_key: { to_table: :users }, type: :uuid

      t.timestamps
    end

    add_index :list_collaborations, [ :list_id, :user_id ], unique: true
    add_index :list_collaborations, :permission
    add_index :list_collaborations, :invitation_token, unique: true
  end
end
