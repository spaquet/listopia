# == Schema Information
#
# Table name: ai_agent_resources
#
#  id                  :uuid             not null, primary key
#  config              :jsonb            not null
#  description         :text
#  enabled             :boolean          default(TRUE), not null
#  permission          :integer          default("read_only"), not null
#  resource_identifier :string
#  resource_type       :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  ai_agent_id         :uuid             not null
#
# Indexes
#
#  index_ai_agent_resources_on_ai_agent_id    (ai_agent_id)
#  index_ai_agent_resources_on_enabled        (enabled)
#  index_ai_agent_resources_on_resource_type  (resource_type)
#
# Foreign Keys
#
#  fk_rails_...  (ai_agent_id => ai_agents.id)
#

class AiAgentResource < ApplicationRecord
  belongs_to :ai_agent

  RESOURCE_TYPES = %w[
    list list_item web_search calendar slack
    google_drive external_api database_query agent
  ].freeze

  enum :permission, {
    read_only:       0,
    write_only:      1,
    read_write:      2,
    expect_response: 3
  }, prefix: true

  validates :resource_type, presence: true, inclusion: { in: RESOURCE_TYPES }
  validates :permission, presence: true

  scope :enabled, -> { where(enabled: true) }
  scope :by_type, ->(type) { where(resource_type: type) }
  scope :writable, -> { where(permission: [ :write_only, :read_write ]) }
end
