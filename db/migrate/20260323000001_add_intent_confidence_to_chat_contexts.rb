class AddIntentConfidenceToChatContexts < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_contexts, :intent_confidence, :float, default: 0.0, comment: "Confidence score for intent detection (0.0-1.0)"
  end
end
