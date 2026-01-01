class CreateModerationLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :moderation_logs, id: :uuid do |t|
      t.references :chat, type: :uuid, foreign_key: true
      t.references :message, type: :uuid, foreign_key: true, null: true
      t.references :user, type: :uuid, foreign_key: true
      t.references :organization, type: :uuid, foreign_key: true

      t.integer :violation_type, default: 0
      t.integer :action_taken, default: 0

      t.jsonb :detected_patterns, default: []
      t.jsonb :moderation_scores, default: {}
      t.string :prompt_injection_risk, default: "low"
      t.text :details

      t.timestamps
    end

    add_index :moderation_logs, [ :organization_id, :created_at ]
    add_index :moderation_logs, [ :user_id, :created_at ]
    add_index :moderation_logs, :violation_type
    add_index :moderation_logs, :action_taken
  end
end
