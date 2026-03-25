class CreateAiAgentResources < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_agent_resources, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :ai_agent,        type: :uuid, null: false, foreign_key: true

      # What resource type this connects to
      t.string   :resource_type,     null: false
      # Values: "list", "list_item", "web_search", "calendar", "slack",
      #         "google_drive", "external_api", "database_query"

      t.string   :resource_identifier  # optional: specific list ID, URL pattern, etc.

      # Permission level for this resource
      t.integer  :permission,         null: false, default: 0
      # enum permission: { read_only: 0, write_only: 1, read_write: 2, expect_response: 3 }

      t.text     :description          # Human-readable description of why this resource is used
      t.jsonb    :config, null: false, default: '{}'

      t.boolean  :enabled, null: false, default: true

      t.timestamps

      t.index :resource_type
      t.index :enabled
    end
  end
end
