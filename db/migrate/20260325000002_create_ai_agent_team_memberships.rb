class CreateAiAgentTeamMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_agent_team_memberships, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :ai_agent, type: :uuid, null: false, foreign_key: true
      t.references :team,     type: :uuid, null: false, foreign_key: true

      t.timestamps

      t.index [ :ai_agent_id, :team_id ], unique: true
    end
  end
end
