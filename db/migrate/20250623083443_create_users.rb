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

      # Profile fields
      t.string :avatar_url
      t.text :bio

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :email_verification_token, unique: true
    add_index :users, [ :provider, :uid ], unique: true
  end
end

# db/migrate/003_create_magic_links.rb
class CreateMagicLinks < ActiveRecord::Migration[8.0]
  def change
    create_table :magic_links, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :token, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end

    add_index :magic_links, :token, unique: true
    add_index :magic_links, :expires_at
    add_index :magic_links, :used_at
  end
end

# db/migrate/004_create_lists.rb
class CreateLists < ActiveRecord::Migration[8.0]
  def change
    create_table :lists, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :title, null: false
      t.text :description
      t.integer :status, default: 0, null: false

      # Sharing settings
      t.boolean :is_public, default: false
      t.string :public_slug, unique: true

      # Metadata
      t.json :metadata, default: {}
      t.string :color_theme, default: 'blue'

      t.timestamps
    end

    add_index :lists, :user_id
    add_index :lists, :status
    add_index :lists, :public_slug, unique: true
    add_index :lists, :is_public
    add_index :lists, :created_at
  end
end

# db/migrate/005_create_list_collaborations.rb
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

# db/migrate/006_create_list_items.rb
class CreateListItems < ActiveRecord::Migration[8.0]
  def change
    create_table :list_items, id: :uuid do |t|
      t.references :list, null: false, foreign_key: true, type: :uuid
      t.references :assigned_user, foreign_key: { to_table: :users }, type: :uuid

      t.string :title, null: false
      t.text :description
      t.integer :item_type, default: 0, null: false
      t.integer :priority, default: 1, null: false

      # Completion tracking
      t.boolean :completed, default: false
      t.datetime :completed_at

      # Scheduling
      t.datetime :due_date
      t.datetime :reminder_at

      # Ordering
      t.integer :position, default: 0

      # Additional data
      t.string :url # for link type items
      t.json :metadata, default: {}

      t.timestamps
    end

    add_index :list_items, :list_id
    add_index :list_items, :assigned_user_id
    add_index :list_items, :item_type
    add_index :list_items, :priority
    add_index :list_items, :completed
    add_index :list_items, :due_date
    add_index :list_items, :position
    add_index :list_items, :created_at
  end
end

# db/migrate/007_add_indexes_for_performance.rb
class AddIndexesForPerformance < ActiveRecord::Migration[8.0]
  def change
    # Composite indexes for common queries
    add_index :list_items, [ :list_id, :completed ]
    add_index :list_items, [ :list_id, :priority ]
    add_index :list_items, [ :assigned_user_id, :completed ]
    add_index :list_items, [ :due_date, :completed ]

    # Indexes for list queries
    add_index :lists, [ :user_id, :status ]
    add_index :lists, [ :user_id, :created_at ]

    # Indexes for collaboration queries
    add_index :list_collaborations, [ :user_id, :permission ]
  end
end
