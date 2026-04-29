class CreateAiAgents < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_agents, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      # Identity
      t.string   :name,           null: false
      t.text     :description
      t.string   :slug,           null: false

      # Ownership / Scope
      t.integer  :scope,          null: false, default: 0
      # enum scope: { system_agent: 0, org_agent: 1, team_agent: 2, user_agent: 3 }

      t.references :user,         type: :uuid, foreign_key: true, null: true
      t.references :organization, type: :uuid, foreign_key: true, null: true

      # Core Agent Definition
      t.text     :prompt,         null: false
      t.jsonb    :parameters,     null: false, default: '{}'

      # Status / Availability
      t.integer  :status,         null: false, default: 0
      # enum status: { draft: 0, active: 1, paused: 2, archived: 3 }

      # Safety Controls
      t.integer  :max_tokens_per_run,    default: 4000
      t.integer  :max_tokens_per_day,    default: 50_000
      t.integer  :max_tokens_per_month,  default: 500_000
      t.integer  :timeout_seconds,       default: 120
      t.integer  :max_steps,             default: 20
      t.integer  :rate_limit_per_hour,   default: 10

      # Token usage tracking
      t.integer  :tokens_used_today,     default: 0
      t.integer  :tokens_used_this_month, default: 0
      t.date     :tokens_today_date
      t.integer  :tokens_month_year

      # LLM Model Selection
      t.string   :model,                 default: 'gpt-4o-mini'

      # Metadata / Future Evolution
      t.jsonb    :metadata,       null: false, default: '{}'

      # Stats (denormalized for fast display)
      t.integer  :run_count,             default: 0
      t.integer  :success_count,         default: 0
      t.float    :average_rating,        default: nil

      t.timestamps
      t.datetime :discarded_at

      t.index :scope
      t.index :status
      t.index :discarded_at
      t.index [ :organization_id, :slug ], unique: true
      t.index [ :user_id, :slug ],         unique: true
      t.index :run_count
    end
  end
end
