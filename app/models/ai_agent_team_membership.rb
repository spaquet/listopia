# == Schema Information
#
# Table name: ai_agent_team_memberships
#
#  id          :uuid             not null, primary key
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  ai_agent_id :uuid             not null
#  team_id     :uuid             not null
#
# Indexes
#
#  index_ai_agent_team_memberships_on_ai_agent_id              (ai_agent_id)
#  index_ai_agent_team_memberships_on_ai_agent_id_and_team_id  (ai_agent_id,team_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_1a2b3c4d5e  (ai_agent_id => ai_agents.id)
#  fk_rails_2b3c4d5e6f  (team_id => teams.id)
#

class AiAgentTeamMembership < ApplicationRecord
  belongs_to :ai_agent
  belongs_to :team

  validates :ai_agent_id, uniqueness: { scope: :team_id }
  validate  :agent_is_team_scoped

  private

  def agent_is_team_scoped
    errors.add(:ai_agent, "must be a team-scoped agent") unless ai_agent&.team_agent?
  end
end
