# app/models/calendar_event.rb
# == Schema Information
#
# Table name: calendar_events
#
#  id                        :uuid             not null, primary key
#  attendees                 :jsonb            not null
#  description               :text
#  embedding                 :vector(1536)
#  embedding_generated_at    :datetime
#  end_time                  :timestamptz
#  is_organizer              :boolean          default(FALSE)
#  organizer_email           :string
#  organizer_name            :string
#  provider                  :string           not null
#  requires_embedding_update :boolean          default(FALSE), not null
#  start_time                :timestamptz      not null
#  status                    :string           default("confirmed")
#  summary                   :string           not null
#  timezone                  :string
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  connector_account_id      :uuid
#  external_event_id         :string           not null
#  organization_id           :uuid             not null
#  user_id                   :uuid             not null
#
# Indexes
#
#  index_calendar_events_on_attendees               (attendees) USING gin
#  index_calendar_events_on_connector_account_id    (connector_account_id)
#  index_calendar_events_on_external_event_id       (external_event_id) UNIQUE
#  index_calendar_events_on_organization_id         (organization_id)
#  index_calendar_events_on_user_id                 (user_id)
#  index_calendar_events_on_user_id_and_start_time  (user_id,start_time)
#
# Foreign Keys
#
#  fk_rails_...  (connector_account_id => connector_accounts.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (user_id => users.id)
#

class CalendarEvent < ApplicationRecord
  # Embedding & Search
  include SearchableEmbeddable
  include PgSearch::Model

  # Associations
  belongs_to :user
  belongs_to :organization
  belongs_to :connector_account, class_name: "Connectors::Account", optional: true

  # Enums
  enum :provider, { google_calendar: "google_calendar", microsoft_outlook: "microsoft_outlook" }
  enum :status, { confirmed: "confirmed", tentative: "tentative", cancelled: "cancelled" }

  # Validations
  validates :user_id, :organization_id, presence: true
  validates :external_event_id, presence: true, uniqueness: true
  validates :provider, presence: true, inclusion: { in: providers.keys }
  validates :summary, presence: true
  validates :start_time, presence: true
  validates :status, presence: true, inclusion: { in: statuses.keys }

  # Full-text search scope
  pg_search_scope :search_by_keyword,
    against: { summary: "A", description: "B", organizer_email: "C", organizer_name: "D" },
    using: { tsearch: { prefix: true } }

  # Scopes
  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :for_organization, ->(org) { where(organization_id: org.id) }
  scope :in_range, ->(start_time, end_time) {
    where("start_time < ? AND (end_time IS NULL OR end_time > ?)", end_time, start_time)
  }
  scope :with_attendee_email, ->(email) {
    where("attendees @> ?", [ { email: email } ].to_json)
  }
  scope :upcoming, -> { where("start_time > ?", Time.current) }
  scope :past, -> { where("start_time <= ?", Time.current) }

  # Methods for search/embedding
  def content_for_embedding
    "#{summary}\n\n#{description}\n\nAttendees: #{attendee_names.join(', ')}\n\nOrganizer: #{organizer_email}"
  end

  def content_changed?
    summary_changed? || description_changed?
  end

  # Extract attendee emails from jsonb
  def attendee_emails
    attendees.map { |a| a["email"] || a[:email] }.compact
  end

  # Extract attendee names from jsonb
  def attendee_names
    attendees.map { |a| a["displayName"] || a["name"] || a[:displayName] || a[:name] || (a["email"] || a[:email])&.split("@")&.first }.compact
  end

  # Check if event overlaps with another
  def overlaps_with?(other_event)
    return false if other_event.start_time >= end_time || (other_event.end_time && other_event.end_time <= start_time)
    true
  end
end
