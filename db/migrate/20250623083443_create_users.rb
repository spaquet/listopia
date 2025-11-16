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

      # Localization
      t.string :locale, limit: 10, default: "en", null: false
      t.string :timezone, limit: 50, default: "UTC", null: false

      # Profile fields
      t.string :avatar_url
      t.text :bio

      # Account status tracking
      t.string :status, default: 'active', null: false

      # Sign-in tracking for admin insights
      t.datetime :last_sign_in_at
      t.string :last_sign_in_ip
      t.integer :sign_in_count, default: 0, null: false

      # Soft delete flag
      t.datetime :discarded_at

      # Invitation
      t.boolean :invited_by_admin, default: false

      # Suspension fields
      t.datetime :suspended_at
      t.text :suspended_reason
      t.uuid :suspended_by_id

      # Deactivation tracking
      t.datetime :deactivated_at
      t.text :deactivated_reason

      # Admin notes and metadata for audit trail
      t.text :admin_notes
      t.jsonb :account_metadata, default: {}

      # Organization context
      t.uuid :current_organization_id

      t.timestamps
    end

    # Basic indexes
    add_index :users, :email, unique: true
    add_index :users, :current_organization_id
    add_index :users, :email_verification_token, unique: true
    add_index :users, [ :provider, :uid ], unique: true
    add_index :users, :locale
    add_index :users, :timezone

    # User management indexes
    add_index :users, :status
    add_index :users, :last_sign_in_at
    add_index :users, :suspended_at
    add_index :users, :deactivated_at
    add_index :users, :discarded_at
    add_index :users, :account_metadata, using: :gin
    add_index :users, :invited_by_admin

    # Foreign key for suspended_by
    add_foreign_key :users, :users, column: :suspended_by_id
  end
end
