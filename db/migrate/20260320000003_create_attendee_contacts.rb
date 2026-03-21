class CreateAttendeeContacts < ActiveRecord::Migration[8.0]
  def change
    create_table :attendee_contacts, id: :uuid do |t|
      t.uuid :organization_id, null: false
      t.uuid :user_id
      t.string :email, null: false
      t.string :display_name
      t.string :title
      t.string :company
      t.string :location
      t.text :bio
      t.string :avatar_url
      t.string :linkedin_url
      t.string :github_username
      t.string :twitter_url
      t.string :website_url
      t.jsonb :linkedin_data
      t.jsonb :github_data
      t.jsonb :clearbit_data
      t.string :enrichment_status, default: "pending"
      t.datetime :enriched_at

      t.timestamps
    end

    add_foreign_key :attendee_contacts, :organizations, column: :organization_id
    add_foreign_key :attendee_contacts, :users, column: :user_id, on_delete: :nullify

    add_index :attendee_contacts, [:organization_id, :email], unique: true
    add_index :attendee_contacts, [:organization_id, :enrichment_status]
    add_index :attendee_contacts, :enrichment_status
    add_index :attendee_contacts, :enriched_at
  end
end
