class AddCompletedAtToListItems < ActiveRecord::Migration[8.0]
  def change
    add_column :list_items, :completed_at, :datetime, null: true
    add_index :list_items, :completed_at
  end
end
