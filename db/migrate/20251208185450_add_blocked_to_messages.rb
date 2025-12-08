class AddBlockedToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :blocked, :boolean, default: false, if_not_exists: true
    add_index :messages, :blocked, if_not_exists: true
  end
end
