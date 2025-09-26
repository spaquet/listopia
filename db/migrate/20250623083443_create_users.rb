# db/migrate/20250623083443_create_users.rb
class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users, id: :uuid do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.string :password_digest, null: false

      # Email verification
      t.string :email_verification_token
      t.datetime :email_verified_at

      # OAuth fields (for future use)
      t.string :provider
      t.string :uid

      #
      t.string :locale, limit: 10, default: "en", null: false
      t.string :timezone, limit: 50, default: "UTC", null: false

      # Profile fields
      t.string :avatar_url
      t.text :bio

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :email_verification_token, unique: true
    add_index :users, [ :provider, :uid ], unique: true
    add_index :users, :locale
    add_index :users, :timezone
  end
end
