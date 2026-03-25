class AddParentRequirementsToChatContexts < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_contexts, :parent_requirements, :jsonb, default: {}, comment: "Parent item requirements extracted from planning domain"
  end
end
