class CreateAiAgentFeedbacks < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_agent_feedbacks, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :ai_agent_run, type: :uuid, null: false, foreign_key: true
      t.references :ai_agent,     type: :uuid, null: false, foreign_key: true
      t.references :user,         type: :uuid, null: false, foreign_key: true

      # Mirrors MessageFeedback exactly
      t.integer  :rating,         null: false
      # enum rating: { helpful: 1, neutral: 2, unhelpful: 3, harmful: 4 }

      t.integer  :feedback_type
      # enum feedback_type: { accuracy: 0, relevance: 1, speed: 2, quality: 3 }

      t.integer  :helpfulness_score       # 1-5 scale (optional)
      t.text     :comment

      t.timestamps

      t.index :rating
      t.index [ :ai_agent_run_id, :user_id ], unique: true
      t.index [ :user_id, :created_at ]
    end
  end
end
