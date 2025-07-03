# db/migrate/20250703034216_add_counter_caches_to_lists.rb
class AddCounterCachesToLists < ActiveRecord::Migration[8.0]
  def change
    add_column :lists, :list_items_count, :integer, default: 0, null: false
    add_column :lists, :list_collaborations_count, :integer, default: 0, null: false

    # Add index for performance
    add_index :lists, :list_items_count
    add_index :lists, :list_collaborations_count

    # Populate existing data
    reversible do |dir|
      dir.up do
        List.find_each do |list|
          List.reset_counters(list.id, :list_items, :list_collaborations)
        end
      end
    end
  end
end
