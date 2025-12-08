class AddFocusedResourceToChats < ActiveRecord::Migration[8.1]
  def change
    add_column :chats, :focused_resource_type, :string, if_not_exists: true
    add_column :chats, :focused_resource_id, :uuid, if_not_exists: true

    add_index :chats, [:focused_resource_type, :focused_resource_id], if_not_exists: true
  end
end
