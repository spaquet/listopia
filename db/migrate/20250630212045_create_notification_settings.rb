# db/migrate/20250630212045_create_notification_settings.rb
class CreateNotificationSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :notification_settings, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid

      # Channel preferences
      t.boolean :email_notifications, default: true, null: false
      t.boolean :sms_notifications, default: false, null: false
      t.boolean :push_notifications, default: true, null: false

      # Notification type preferences
      t.boolean :collaboration_notifications, default: true, null: false
      t.boolean :list_activity_notifications, default: true, null: false
      t.boolean :item_activity_notifications, default: true, null: false
      t.boolean :status_change_notifications, default: true, null: false

      # Frequency preferences
      t.string :notification_frequency, default: 'immediate', null: false
      # Options: 'immediate', 'daily_digest', 'weekly_digest', 'disabled'

      # Time preferences
      t.time :quiet_hours_start # e.g., 22:00
      t.time :quiet_hours_end   # e.g., 08:00
      t.string :timezone, default: 'UTC'

      t.timestamps
    end

    add_index :notification_settings, :notification_frequency
  end
end
