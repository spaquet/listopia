class AddPlanningContextIdToChats < ActiveRecord::Migration[8.0]
  def change
    add_column :chats, :planning_context_id, :uuid
    add_index :chats, :planning_context_id
    add_foreign_key :chats, :planning_contexts, column: :planning_context_id
  end
end
