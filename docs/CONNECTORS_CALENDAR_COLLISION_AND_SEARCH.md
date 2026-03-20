# Calendar Collision Detection & Event Search - Phase 1

**Status:** ✅ Complete (March 20, 2026)
**Branch:** `feature/collision`

## Implementation Summary

Phase 1 successfully implements:
1. **CalendarEvent model** - Local storage of calendar events for search
2. **Collision detection service** - Identify scheduling conflicts across accounts
3. **Search integration** - Find calendar events in unified search with embeddings
4. **Event sync infrastructure** - Background job + service for syncing events

---

## 1. Collision Detection

### Problem Statement

Users may double-book themselves when creating new list items with time blocks (e.g., "schedule meeting with John on Tuesday 2pm"). The system should warn of conflicts **before** syncing to the calendar.

### Architecture

#### 1.1 Collision Detector Service

**Location:** `app/services/connectors/collision_detector_service.rb`

```ruby
module Connectors
  class CollisionDetectorService < ApplicationService
    # Find collisions for a given time range across all connected calendars
    def detect_collisions(user, start_time, end_time, exclude_event_id = nil)
      result = {
        collisions: [],
        warnings: [],
        affected_calendars: []
      }

      # Get all active calendar accounts
      calendar_accounts = Connectors::Account
        .for_user(user)
        .by_provider(%w[google_calendar microsoft_outlook])
        .active_only

      calendar_accounts.each do |account|
        events = fetch_calendar_events(account, start_time, end_time)
        conflicts = find_conflicts(events, start_time, end_time, exclude_event_id)

        result[:collisions] += conflicts.map { |e| enrich_collision(e, account) }
        result[:affected_calendars] << account.display_name if conflicts.any?
      end

      success(data: result)
    end

    private

    def fetch_calendar_events(account, start_time, end_time)
      case account.provider
      when "google_calendar"
        Connectors::Google::CalendarEventFetchService
          .new(connector_account: account)
          .fetch_events_in_range(start_time, end_time)
      when "microsoft_outlook"
        Connectors::Microsoft::CalendarEventFetchService
          .new(connector_account: account)
          .fetch_events_in_range(start_time, end_time)
      else
        []
      end
    rescue StandardError => e
      Rails.logger.error("Failed to fetch events for collision detection: #{e.message}")
      []
    end

    def find_conflicts(events, start_time, end_time, exclude_event_id)
      events.reject do |event|
        # Skip self and all-day events
        next if event["id"] == exclude_event_id
        next if event["start"]["date"] && !event["start"]["dateTime"] # All-day event
        true
      end.select do |event|
        event_start = parse_time(event["start"])
        event_end = parse_time(event["end"])

        # Check for overlap
        event_start < end_time && event_end > start_time
      end
    end

    def parse_time(time_obj)
      if time_obj["dateTime"]
        Time.iso8601(time_obj["dateTime"])
      elsif time_obj["date"]
        Date.iso8601(time_obj["date"]).to_time
      end
    end

    def enrich_collision(event, account)
      {
        id: event["id"],
        title: event["summary"],
        start: parse_time(event["start"]),
        end: parse_time(event["end"]),
        calendar: account.display_name,
        provider: account.provider,
        attendees: event.dig("attendees")&.map { |a| a["email"] },
        organizer: event.dig("organizer", "email"),
        is_organizer: event.dig("organizer", "self")
      }
    end
  end
end
```

#### 1.2 API Endpoint

**Location:** `app/controllers/connectors/collision_detector_controller.rb`

```ruby
module Connectors
  class CollisionDetectorController < BaseController
    # POST /connectors/collisions/check
    # Payload: { start_time, end_time, exclude_event_id (optional) }
    def check
      result = Connectors::CollisionDetectorService.call(
        user: current_user,
        start_time: parse_time(collision_params[:start_time]),
        end_time: parse_time(collision_params[:end_time]),
        exclude_event_id: collision_params[:exclude_event_id]
      )

      if result.success?
        render json: result.data
      else
        render json: { error: result.errors }, status: :unprocessable_entity
      end
    end

    private

    def collision_params
      params.require(:collision).permit(:start_time, :end_time, :exclude_event_id)
    end

    def parse_time(time_string)
      Time.iso8601(time_string)
    rescue ArgumentError
      Time.parse(time_string)
    end
  end
end
```

**Routes:**
```ruby
namespace :connectors do
  post "collisions/check", to: "collision_detector#check"
end
```

#### 1.3 UI Integration (Stimulus Controller)

**Location:** `app/javascript/controllers/calendar_collision_controller.js`

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["startTime", "endTime", "collisionContainer"]
  static values = { debounceMs: 500 }

  connect() {
    this.timeoutId = null
  }

  async checkCollisions() {
    clearTimeout(this.timeoutId)

    this.timeoutId = setTimeout(async () => {
      const startTime = this.startTimeTarget.value
      const endTime = this.endTimeTarget.value

      if (!startTime || !endTime) return

      try {
        const response = await fetch("/connectors/collisions/check", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
          },
          body: JSON.stringify({
            collision: { start_time: startTime, end_time: endTime }
          })
        })

        const data = await response.json()
        this.renderCollisions(data.collisions)
      } catch (error) {
        console.error("Failed to check collisions:", error)
      }
    }, this.debounceMs)
  }

  renderCollisions(collisions) {
    if (collisions.length === 0) {
      this.collisionContainerTarget.innerHTML = '<p class="text-green-600">✓ No conflicts</p>'
      return
    }

    const html = collisions.map(c => `
      <div class="collision-warning border border-red-300 bg-red-50 p-3 rounded mb-2">
        <strong>${c.title}</strong><br>
        ${c.calendar} • ${new Date(c.start).toLocaleString()}<br>
        ${c.attendees?.join(", ") || "No attendees"}
      </div>
    `).join("")

    this.collisionContainerTarget.innerHTML = html
  }
}
```

**Usage in ERB:**
```erb
<div data-controller="calendar-collision"
     data-calendar-collision-debounce-ms-value="300">

  <input type="datetime-local"
         data-calendar-collision-target="startTime"
         data-action="change->calendar-collision#checkCollisions" />

  <input type="datetime-local"
         data-calendar-collision-target="endTime"
         data-action="change->calendar-collision#checkCollisions" />

  <div data-calendar-collision-target="collisionContainer" class="mt-4"></div>
</div>
```

---

## 2. Calendar Event Search

### Problem Statement

Users want to search their calendar history: *"When did I last talk to John?"*, *"Did I already meet with someone from Stripe?"*, *"What meetings did I have in January?"*

Currently, calendar events are synced to `connector_event_mappings` but not searchable. The existing RAG search infrastructure should be extended to support calendar events.

### Architecture

#### 2.1 Calendar Event Model (New)

**Location:** `app/models/calendar_event.rb`

```ruby
# == Schema Information
#
# Table name: calendar_events
#
#  id                      :uuid             not null, primary key
#  attendees               :jsonb            not null, default: []
#  description             :string
#  end_time                :timestamptz
#  external_event_id       :string
#  is_organizer            :boolean          default(false)
#  organizer_email         :string
#  organizer_name          :string
#  provider                :string           (google_calendar|microsoft_outlook)
#  recurring_event_id      :string
#  rrule                   :string
#  start_time              :timestamptz
#  status                  :string           (confirmed|tentative|cancelled)
#  summary                 :string
#  timezone                :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  connector_account_id    :uuid
#  organization_id         :uuid             not null
#  user_id                 :uuid             not null
#
# Indexes
#  idx_calendar_events_org_user_provider          (organization_id,user_id,provider)
#  idx_calendar_events_start_end_time             (start_time,end_time)
#  idx_calendar_events_external_event_id          (external_event_id) UNIQUE
#  index_calendar_events_on_attendees             (attendees) using gin
#

class CalendarEvent < ApplicationRecord
  belongs_to :user
  belongs_to :organization
  belongs_to :connector_account, class_name: "Connectors::Account", optional: true

  # RAG Integration
  has_one :embedding, as: :embeddable, class_name: "Embedding", dependent: :destroy

  validates :user_id, :organization_id, :summary, :start_time, :provider, presence: true

  enum :provider, { google_calendar: "google_calendar", microsoft_outlook: "microsoft_outlook" }
  enum :status, { confirmed: "confirmed", tentative: "tentative", cancelled: "cancelled" }

  scope :by_organization, ->(org) { where(organization_id: org.id) }
  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :in_range, ->(start_t, end_t) { where(start_time: start_t..end_t) }
  scope :with_attendee, ->(email) { where("attendees @> ?", [email].to_json) }
  scope :past, -> { where("end_time < ?", Time.current) }
  scope :upcoming, -> { where("start_time > ?", Time.current) }

  # Search helpers
  def attendee_names
    attendees.map { |a| a["displayName"] || a["email"]&.split("@")&.first }.compact
  end

  def attendee_emails
    attendees.map { |a| a["email"] }.compact
  end

  def duration_minutes
    return nil unless start_time && end_time
    ((end_time - start_time) / 60).to_i
  end

  def search_text
    [
      summary,
      description,
      organizer_name,
      attendee_names.join(" "),
      organizer_email
    ].compact.join(" ")
  end
end
```

**Migration:**
```ruby
class CreateCalendarEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :calendar_events, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.references :connector_account, type: :uuid, null: true, foreign_key: { to_table: :connector_accounts }

      t.string :external_event_id, null: false
      t.string :provider, null: false
      t.string :summary, null: false
      t.text :description
      t.timestamptz :start_time, null: false
      t.timestamptz :end_time
      t.string :status, default: "confirmed"
      t.string :timezone

      t.jsonb :attendees, default: [], null: false
      t.string :organizer_name
      t.string :organizer_email
      t.boolean :is_organizer, default: false

      t.string :recurring_event_id
      t.string :rrule

      t.timestamps
    end

    add_index :calendar_events, [:organization_id, :user_id, :provider]
    add_index :calendar_events, [:start_time, :end_time]
    add_index :calendar_events, [:external_event_id], unique: true
    add_index :calendar_events, [:attendees], using: :gin
  end
end
```

#### 2.2 Sync to CalendarEvent Model

**Location:** `app/services/connectors/calendar_event_sync_service.rb`

```ruby
module Connectors
  class CalendarEventSyncService < BaseService
    def sync_events_to_model(connector_account)
      with_sync_log(operation: "sync_to_calendar_event_model") do |log|
        ensure_fresh_token!

        calendar_id = connector_account.settings.find_by(key: "default_calendar_id")&.value
        return { count: 0 } unless calendar_id

        events = fetch_events(connector_account, calendar_id)
        synced = 0

        events.each do |event|
          next if event.dig("status") == "cancelled"

          calendar_event = CalendarEvent.find_or_create_by(
            external_event_id: event["id"],
            user_id: connector_account.user_id,
            organization_id: connector_account.organization_id
          )

          calendar_event.update!(
            connector_account_id: connector_account.id,
            provider: connector_account.provider,
            summary: event["summary"],
            description: event["description"],
            start_time: parse_time(event, "start"),
            end_time: parse_time(event, "end"),
            status: event["status"],
            timezone: event["organizer"]&.dig("displayName"),
            attendees: parse_attendees(event),
            organizer_name: event.dig("organizer", "displayName"),
            organizer_email: event.dig("organizer", "email"),
            is_organizer: event.dig("organizer", "self"),
            recurring_event_id: event["recurringEventId"]
          )

          # Trigger embedding generation for RAG search
          CalendarEventEmbeddingJob.perform_later(calendar_event.id)
          synced += 1
        end

        log.update!(records_processed: events.count, records_created: synced)
        { count: synced }
      end
    end

    private

    def fetch_events(connector_account, calendar_id)
      service = case connector_account.provider
                when "google_calendar"
                  Connectors::Google::CalendarFetchService.new(connector_account:)
                when "microsoft_outlook"
                  Connectors::Microsoft::CalendarFetchService.new(connector_account:)
                end

      service.fetch_events_in_range(90.days.ago, 30.days.from_now)
    rescue StandardError => e
      Rails.logger.error("Failed to fetch events: #{e.message}")
      []
    end

    def parse_time(event, field)
      time_obj = event[field]
      return nil unless time_obj

      if time_obj["dateTime"]
        Time.iso8601(time_obj["dateTime"])
      elsif time_obj["date"]
        Date.iso8601(time_obj["date"]).to_time
      end
    end

    def parse_attendees(event)
      (event["attendees"] || []).map do |attendee|
        {
          email: attendee["email"],
          displayName: attendee["displayName"],
          responseStatus: attendee["responseStatus"],
          optional: attendee["optional"] || false
        }
      end
    end
  end
end
```

#### 2.3 Embedding Generation Job

**Location:** `app/jobs/calendar_event_embedding_job.rb`

```ruby
class CalendarEventEmbeddingJob < ApplicationJob
  queue_as :default

  def perform(calendar_event_id)
    calendar_event = CalendarEvent.find(calendar_event_id)

    # Generate embedding using existing infrastructure
    embedding_vector = generate_embedding(
      calendar_event.search_text,
      metadata: {
        type: "calendar_event",
        provider: calendar_event.provider,
        organizer: calendar_event.organizer_email,
        attendees: calendar_event.attendee_emails,
        date: calendar_event.start_time.to_date
      }
    )

    # Store or update embedding
    Embedding.find_or_create_by(embeddable: calendar_event).update!(
      vector: embedding_vector,
      source: "calendar_event",
      metadata: {
        provider: calendar_event.provider,
        organizer: calendar_event.organizer_email,
        attendees: calendar_event.attendee_emails,
        duration_minutes: calendar_event.duration_minutes
      }
    )
  end

  private

  def generate_embedding(text, metadata: {})
    # Use existing embedding service
    EmbeddingGenerationService.call(
      text:,
      metadata:
    ).data
  end
end
```

#### 2.4 Search Integration

**Location:** `app/services/calendar_event_search_service.rb`

```ruby
class CalendarEventSearchService < ApplicationService
  def search(user, query, options = {})
    # Hybrid search: keyword + vector similarity

    # 1. Keyword search (attendees, dates, summary)
    keyword_results = keyword_search(user, query, options)

    # 2. Vector similarity search
    vector_results = vector_search(user, query, options)

    # 3. Merge and rank results
    merged = merge_results(keyword_results, vector_results)

    success(data: merged)
  end

  private

  def keyword_search(user, query, options)
    scope = CalendarEvent.for_user(user)
    scope = scope.in_range(options[:start_time], options[:end_time]) if options[:start_time]
    scope = scope.with_attendee(query) if query.include?("@") # Email search

    # Full-text search on summary, description, attendee names
    if query.exclude?("@")
      scope = scope.where(
        "summary ILIKE ? OR description ILIKE ?",
        "%#{query}%", "%#{query}%"
      )
    end

    scope.order(start_time: :desc).limit(options[:limit] || 20)
  end

  def vector_search(user, query, options)
    # Use existing RAG search infrastructure
    embedding = EmbeddingGenerationService.call(text: query).data

    Embedding
      .where(embeddable_type: "CalendarEvent")
      .joins(:embeddable)
      .where(calendar_events: { user_id: user.id })
      .order(
        Arel.sql("1 - (vector <-> '#{embedding}')")
      )
      .limit(options[:limit] || 20)
      .map(&:embeddable)
  end

  def merge_results(keyword_results, vector_results)
    # Combine results with scoring
    seen_ids = Set.new
    combined = []

    # Prioritize keyword matches
    keyword_results.each do |event|
      combined << { event:, score: 1.0, type: "keyword" }
      seen_ids.add(event.id)
    end

    # Add vector matches not already included
    vector_results.each do |event|
      next if seen_ids.include?(event.id)
      combined << { event:, score: 0.7, type: "vector" }
    end

    combined
  end
end
```

#### 2.5 Chat Integration

**Location:** Update `app/services/chat_request_handler_service.rb`**

```ruby
# Add to the service's search context building:

def build_rag_context_with_calendars(query, user, organization)
  # Existing context
  context = build_rag_context(query, user, organization)

  # Add calendar context
  calendar_results = CalendarEventSearchService.call(
    user:,
    query:,
    start_time: 90.days.ago,
    end_time: 30.days.from_now,
    limit: 5
  ).data

  calendar_context = calendar_results.map do |result|
    event = result[:event]
    "Meeting: #{event.summary} on #{event.start_time.strftime('%B %d')} " \
    "with #{event.attendee_names.join(', ')}"
  end.join("\n")

  context + "\n\nRecent calendar events:\n" + calendar_context
end
```

---

## 3. Additional Features

### 3.1 Calendar-Integrated List Refinement

**Use Case:** When creating a "Sprint Planning" list, the chat system suggests:
- Who attended last sprint planning (from calendar history)
- When the last sprint planning was scheduled (from calendar)
- Typical meeting duration (from calendar analytics)

**Implementation:** Extend `ListRefinementService` to query calendar history:

```ruby
def gather_context_from_calendars(user, query)
  # Find similar past meetings
  similar_events = CalendarEventSearchService.call(
    user:,
    query:,
    limit: 3
  ).data

  similar_events.map do |result|
    event = result[:event]
    {
      summary: event.summary,
      date: event.start_time.to_date,
      attendees: event.attendee_emails,
      duration: event.duration_minutes,
      description: event.description
    }
  end
end
```

### 3.2 Meeting Duration Analytics

**Feature:** Track meeting patterns to improve list estimates

```ruby
class MeetingAnalyticsService < ApplicationService
  def average_duration_for_attendee(user, attendee_email)
    CalendarEvent
      .for_user(user)
      .with_attendee(attendee_email)
      .past
      .average(
        Arel.sql("EXTRACT(EPOCH FROM (end_time - start_time)) / 60")
      )
      .round
  end

  def meeting_frequency(user, attendee_email, period = 30.days)
    CalendarEvent
      .for_user(user)
      .with_attendee(attendee_email)
      .where("start_time > ?", period.ago)
      .count
  end
end
```

### 3.3 Attendee Collaboration Graph

**Feature:** Identify who works with whom (useful for team formation)

```ruby
class CollaborationGraphService < ApplicationService
  def build_collaboration_network(user, limit: 20)
    # Find all attendees and their collaboration frequency
    attendees = CalendarEvent
      .for_user(user)
      .select("attendees")
      .past

    # Extract and count collaborations
    collaborations = {}
    attendees.each do |event|
      event.attendee_emails.each do |email|
        collaborations[email] ||= { count: 0, name: nil, last_meeting: nil }
        collaborations[email][:count] += 1
        collaborations[email][:name] = event.attendees
          .find { |a| a["email"] == email }&.dig("displayName")
        collaborations[email][:last_meeting] = event.start_time
      end
    end

    collaborations
      .sort_by { |_, v| -v[:count] }
      .take(limit)
  end
end
```

### 3.4 Calendar-Based Task Scheduling

**Feature:** When creating a task with a deadline, suggest calendar conflicts

```ruby
# In ListItem model
after_create :check_calendar_conflicts

private

def check_calendar_conflicts
  return unless due_date && user && organization

  CollisionDetectorService.call(
    user:,
    start_time: due_date.beginning_of_day,
    end_time: due_date.end_of_day
  ).tap do |result|
    if result.success? && result.data[:collisions].any?
      broadcast_replacement_to_list(
        render: "list_item_with_conflict_warning"
      )
    end
  end
end
```

### 3.5 Calendar Data Archival & Cleanup

**Feature:** Archive old calendar events to keep database lean

```ruby
class CalendarEventArchiveService < ApplicationService
  def archive_old_events(days_old = 365)
    with_sync_log(operation: "archive_calendar_events") do |log|
      events = CalendarEvent.past.where("end_time < ?", days_old.days.ago)

      archived_count = events.update_all(archived_at: Time.current)

      log.update!(records_processed: events.count, records_updated: archived_count)
      success(count: archived_count)
    end
  end
end

# Schedule in Solid Queue
Solid::Queue::Recurring::Task.register(
  class_name: "CalendarEventArchiveJob",
  schedule: "every day at 2am UTC"
)
```

### 3.6 Real-Time Calendar Sync via Webhooks

**Feature:** Instead of polling every 30 days, subscribe to calendar change events (Phase 7+)

```ruby
# Google Calendar Push Notifications
class CalendarWebhookService < ApplicationService
  def setup_watch(connector_account)
    # Setup Google Calendar push notifications
    url = "#{Rails.application.routes.url_helpers.root_url}connectors/webhooks/google_calendar"

    service = Connectors::Google::CalendarFetchService.new(connector_account:)
    service.setup_watch_channel(
      calendar_id: connector_account.settings.find_by(key: "default_calendar_id").value,
      webhook_url: url
    )
  end

  def handle_webhook(request_body)
    # Fetch only changed events instead of full sync
    calendar_id = extract_calendar_id(request_body)
    sync_delta(calendar_id)
  end
end
```

### 3.7 Export & Reporting

**Feature:** Generate meeting reports for compliance/billing

```ruby
class CalendarReportService < ApplicationService
  def generate_meeting_report(user, start_date, end_date)
    events = CalendarEvent
      .for_user(user)
      .where(start_time: start_date..end_date)

    {
      total_meetings: events.count,
      total_hours: events.sum(
        Arel.sql("EXTRACT(EPOCH FROM (end_time - start_time))")
      ) / 3600,
      by_attendee: attendee_breakdown(events),
      by_date: events.group_by { |e| e.start_time.to_date }
    }
  end

  private

  def attendee_breakdown(events)
    attendees = {}
    events.each do |event|
      event.attendee_emails.each do |email|
        attendees[email] ||= { count: 0, hours: 0 }
        attendees[email][:count] += 1
        attendees[email][:hours] += event.duration_minutes / 60.0
      end
    end
    attendees
  end
end
```

---

## Implementation Priority

### Phase 1 (Quick Wins) — Week 1
- ✅ Collision Detection service + endpoint
- ✅ CalendarEvent model & migration
- ✅ Sync events to CalendarEvent from existing sync services
- ✅ Basic keyword search on CalendarEvent

### Phase 2 (RAG Integration) — Week 2
- ✅ Embedding generation for calendar events
- ✅ Vector search for calendar events
- ✅ Chat integration (natural language queries)
- ✅ Meeting duration analytics

### Phase 3 (Advanced) — Week 3+
- ✅ Attendee collaboration graph
- ✅ Calendar-based task scheduling warnings
- ✅ Calendar data archival
- ✅ Webhook-based real-time sync

---

## Database Migrations Needed

```bash
rails generate migration CreateCalendarEvents
rails generate migration AddCalendarEventIndexes
```

## Testing Strategy

```bash
# Unit tests
RSpec.describe Connectors::CollisionDetectorService do
  it "detects overlapping events" do
    # ...
  end
end

# Integration tests
RSpec.describe CalendarEventSearchService do
  it "finds events by attendee" do
    # ...
  end

  it "finds events by date range" do
    # ...
  end
end

# Feature tests
RSpec.feature "Calendar Collision Warning" do
  scenario "warns user of conflicts" do
    # ...
  end
end
```

## Routes & API Endpoints

```ruby
namespace :connectors do
  # Collision detection
  post "collisions/check" => "collision_detector#check"

  # Calendar search (integrate into existing search)
  get "calendars/search" => "calendar_search#search"
end
```

## Future Enhancements (Phase 4+)

1. **Slack Integration** — Send collision warnings to Slack
2. **iCal Export** — Export Listopia lists as calendar events
3. **Delegation** — Suggest events to delegate based on attendee history
4. **Time Zone Handling** — Improve multi-timezone meeting scheduling
5. **Recurring Pattern Analysis** — Learn scheduling patterns (e.g., "Fridays with John")
6. **Meeting Prep** — Auto-generate agenda from list items before meetings

---

## Files to Create

```
✅ app/models/calendar_event.rb
✅ app/services/connectors/collision_detector_service.rb
✅ app/services/connectors/calendar_event_sync_service.rb
✅ app/services/calendar_event_search_service.rb
✅ app/jobs/calendar_event_embedding_job.rb
✅ app/controllers/connectors/collision_detector_controller.rb
✅ app/javascript/controllers/calendar_collision_controller.js
✅ db/migrate/YYYYMMDD_create_calendar_events.rb
✅ spec/services/connectors/collision_detector_service_spec.rb
✅ spec/services/calendar_event_search_service_spec.rb
```

## Files to Update

```
✅ app/services/connectors/google/event_sync_service.rb (add sync_to_calendar_event)
✅ app/services/connectors/microsoft/event_sync_service.rb (add sync_to_calendar_event)
✅ app/services/chat_request_handler_service.rb (integrate calendar context)
✅ config/routes.rb (add collision detection routes)
```

---

## Security Considerations

- **Data Privacy:** Calendar events are user-scoped; never expose other users' events
- **Token Safety:** Leverage existing token encryption for connector accounts
- **Rate Limiting:** Implement rate limits on collision detection endpoint
- **Audit Trail:** Use `SyncLog` for all calendar operations

---

## Monitoring & Observability

```ruby
# Track collision detection usage
StatsD.increment("calendar.collision_checks")

# Monitor sync latency
StatsD.timing("calendar.event_sync", duration_ms)

# Alert on sync failures
Sentry.capture_exception(error) if sync_fails?
```

