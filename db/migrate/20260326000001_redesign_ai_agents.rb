class RedesignAiAgents < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_agent_interactions, id: :uuid do |t|
      t.references :ai_agent_run, type: :uuid, null: false, foreign_key: true
      t.references :ai_agent_run_step, type: :uuid, null: true, foreign_key: true

      t.text :question, null: false
      t.jsonb :options, default: [], null: false
      t.text :answer

      t.integer :status, default: 0, null: false  # pending=0, answered=1, skipped=2

      t.datetime :asked_at
      t.datetime :answered_at

      t.timestamps
    end

    add_index :ai_agent_interactions, [ :ai_agent_run_id, :status ]
    add_index :ai_agent_interactions, :asked_at

    # Update ai_agents table
    add_column :ai_agents, :instructions, :text
    add_column :ai_agents, :body_context_config, :jsonb, default: {}, null: false
    add_column :ai_agents, :pre_run_questions, :jsonb, default: [], null: false
    add_column :ai_agents, :trigger_config, :jsonb, default: { type: 'manual' }, null: false

    add_column :ai_agents, :embedding, "vector(1536)"
    add_column :ai_agents, :embedding_generated_at, :datetime
    add_column :ai_agents, :requires_embedding_update, :boolean, default: false, null: false

    add_index :ai_agents, :embedding, using: :ivfflat, opclass: :vector_cosine_ops

    # Update ai_agent_runs table
    add_column :ai_agent_runs, :pre_run_answers, :jsonb, default: {}, null: false
    add_column :ai_agent_runs, :trigger_source, :string, default: 'manual', null: false
    add_column :ai_agent_runs, :awaiting_at, :datetime
  end
end
