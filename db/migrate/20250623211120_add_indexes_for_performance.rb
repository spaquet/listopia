# db/migrate/20250623211120_add_indexes_for_performance.rb
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
