# == Schema Information
#
# Table name: events
#
#  id              :uuid             not null, primary key
#  event_data      :jsonb
#  event_type      :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  actor_id        :uuid
#  organization_id :uuid             not null
#
# Indexes
#
#  index_events_on_actor_id                        (actor_id)
#  index_events_on_actor_id_and_created_at         (actor_id,created_at)
#  index_events_on_event_type                      (event_type)
#  index_events_on_organization_id                 (organization_id)
#  index_events_on_organization_id_and_created_at  (organization_id,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (actor_id => users.id)
#  fk_rails_...  (organization_id => organizations.id)
#
class Event < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :organization

  validates :event_type, presence: true
  validates :organization_id, presence: true

  scope :by_type, ->(type) { where(event_type: type) }
  scope :by_actor, ->(user) { where(actor_id: user.id) }
  scope :recent, -> { order(created_at: :desc) }
  scope :since, ->(timestamp) { where("created_at >= ?", timestamp) }

  # Helper to create events from domain models
  def self.emit(event_type, organization_id, actor_id = nil, event_data = {})
    create!(
      event_type:,
      organization_id:,
      actor_id:,
      event_data:
    )
  end
end
