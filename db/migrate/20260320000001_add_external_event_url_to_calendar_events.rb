class AddExternalEventUrlToCalendarEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :calendar_events, :external_event_url, :string
  end
end
