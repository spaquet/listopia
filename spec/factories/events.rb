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
FactoryBot.define do
  factory :event do
    event_type { "MyString" }
    actor { nil }
    event_data { "" }
    created_at { "2026-03-19 16:00:43" }
  end
end
