# db/migrate/20250706232511_create_invitations.rb
class CreateInvitations < ActiveRecord::Migration[8.0]
  def change
    create_table :invitations, id: :uuid do |t|
      t.references :invitable, polymorphic: true, null: false, type: :uuid, index: true
      t.references :user, type: :uuid, foreign_key: true
      t.string :email
      t.string :invitation_token
      t.datetime :invitation_sent_at
      t.datetime :invitation_accepted_at
      t.datetime :invitation_expires_at
      t.references :invited_by, type: :uuid, foreign_key: { to_table: :users }
      t.integer :permission, default: 0, null: false
      t.string :granted_roles, array: true, default: [], null: false
      t.text :message
      t.string :status, default: 'pending', null: false
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :invitations, [ :invitable_id, :invitable_type, :email ], unique: true, name: "index_invitations_on_invitable_and_email", where: "(email IS NOT NULL)"
    add_index :invitations, [ :invitable_id, :invitable_type, :user_id ], unique: true, name: "index_invitations_on_invitable_and_user", where: "(user_id IS NOT NULL)"
    add_index :invitations, :email
    add_index :invitations, :invitation_token, unique: true
    add_index :invitations, :status
    add_index :invitations, :invited_by_id
  end
end
