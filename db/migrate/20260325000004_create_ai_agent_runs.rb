class CreateAiAgentRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_agent_runs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :ai_agent,     type: :uuid, null: false, foreign_key: true
      t.references :user,         type: :uuid, null: false, foreign_key: true
      t.references :organization, type: :uuid, null: false, foreign_key: true

      # Polymorphic invocation context (List, ListItem, Chat, or nil for standalone)
      t.string   :invocable_type   # "List", "ListItem", "Chat"
      t.uuid     :invocable_id

      # Parent run for orchestration
      t.references :parent_run, type: :uuid, foreign_key: { to_table: :ai_agent_runs }, null: true

      # Execution state
      t.integer  :status,         null: false, default: 0
      # enum status: { pending: 0, running: 1, paused: 2, completed: 3, failed: 4, cancelled: 5 }

      # Input
      t.text     :user_input                 # What the user asked the agent to do
      t.jsonb    :input_parameters, null: false, default: '{}'  # Resolved parameter values

      # Output
      t.text     :result_summary             # Human-readable summary of what was done
      t.jsonb    :result_data, null: false, default: '{}'       # Machine-readable results

      # Token tracking (mirrors Message model pattern)
      t.integer  :input_tokens,   default: 0
      t.integer  :output_tokens,  default: 0
      t.integer  :thinking_tokens, default: 0
      t.integer  :total_tokens,   default: 0
      t.integer  :processing_time_ms         # total wall clock time

      # Safety / Progress tracking
      t.integer  :steps_completed, default: 0
      t.integer  :steps_total,     default: 0
      t.text     :error_message
      t.text     :cancellation_reason

      # Timestamps for lifecycle
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :paused_at
      t.datetime :last_activity_at

      t.jsonb    :metadata, null: false, default: '{}'

      t.timestamps

      t.index :status
      t.index [ :invocable_type, :invocable_id ]
      t.index :started_at
      t.index :completed_at
      t.index :last_activity_at
    end
  end
end
