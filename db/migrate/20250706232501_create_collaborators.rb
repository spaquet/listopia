# db/migrate/20250706232501_create_collaborators.rb
class CreateCollaborators < ActiveRecord::Migration[8.0]
  def change
    create_table :collaborators, id: :uuid do |t|
      t.references :collaboratable, polymorphic: true, null: false, type: :uuid, index: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.integer :permission, default: 0, null: false
      t.string :granted_roles, array: true, default: [], null: false
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :collaborators, [ :collaboratable_id, :collaboratable_type, :user_id ], unique: true, name: "index_collaborators_on_collaboratable_and_user"
    add_index :collaborators, :user_id
  end
end
