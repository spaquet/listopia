class CreateAiAgentRunSteps < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_agent_run_steps, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :ai_agent_run, type: :uuid, null: false, foreign_key: true

      t.integer  :step_number,    null: false
      t.string   :step_type,      null: false
      # Values: "llm_call", "tool_call", "resource_read", "resource_write",
      #         "user_interaction", "checkpoint", "error_recovery"

      t.string   :title                   # Short human-readable label for this step
      t.text     :description             # What this step is doing

      t.integer  :status,         null: false, default: 0
      # enum status: { pending: 0, running: 1, completed: 2, failed: 3, skipped: 4 }

      # LLM interaction tracking
      t.text     :prompt_sent              # Prompt used for LLM call (if applicable)
      t.text     :response_received        # Raw LLM response (if applicable)
      t.string   :tool_name               # Tool/function called (if applicable)
      t.jsonb    :tool_input,  null: false, default: '{}'
      t.jsonb    :tool_output, null: false, default: '{}'

      # Token tracking per step
      t.integer  :input_tokens,  default: 0
      t.integer  :output_tokens, default: 0
      t.integer  :processing_time_ms

      t.text     :error_message
      t.datetime :started_at
      t.datetime :completed_at

      t.jsonb    :metadata, null: false, default: '{}'

      t.timestamps

      t.index :status
      t.index :step_type
      t.index [ :ai_agent_run_id, :step_number ], unique: true
    end
  end
end
