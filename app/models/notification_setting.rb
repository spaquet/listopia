# app/models/notification_setting.rb
# == Schema Information
#
# Table name: notification_settings
#
#  id                          :uuid             not null, primary key
#  collaboration_notifications :boolean          default(TRUE), not null
#  email_notifications         :boolean          default(TRUE), not null
#  item_activity_notifications :boolean          default(TRUE), not null
#  list_activity_notifications :boolean          default(TRUE), not null
#  notification_frequency      :string           default("immediate"), not null
#  push_notifications          :boolean          default(TRUE), not null
#  quiet_hours_end             :time
#  quiet_hours_start           :time
#  sms_notifications           :boolean          default(FALSE), not null
#  status_change_notifications :boolean          default(TRUE), not null
#  timezone                    :string           default("UTC")
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  user_id                     :uuid             not null
#
# Indexes
#
#  index_notification_settings_on_notification_frequency  (notification_frequency)
#  index_notification_settings_on_user_id                 (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class NotificationSetting < ApplicationRecord
  belongs_to :user

  # Validation for frequency options
  validates :notification_frequency,
    inclusion: { in: %w[immediate daily_digest weekly_digest disabled] }

  # Validation for timezone
  validates :timezone, presence: true

  # Scope for enabled channels
  scope :email_enabled, -> { where(email_notifications: true) }
  scope :sms_enabled, -> { where(sms_notifications: true) }
  scope :push_enabled, -> { where(push_notifications: true) }

  # Check if notifications are enabled for a specific type
  def notifications_enabled_for?(notification_type)
    case notification_type.to_s
    when "collaboration"
      collaboration_notifications?
    when "list_activity", "list_update"
      list_activity_notifications?
    when "item_activity"
      item_activity_notifications?
    when "status_change"
      status_change_notifications?
    else
      true # Default to enabled for unknown types
    end
  end

  # Check if user is in quiet hours
  def in_quiet_hours?
    return false unless quiet_hours_start && quiet_hours_end

    current_time = Time.current.in_time_zone(timezone).strftime("%H:%M").to_time
    start_time = quiet_hours_start
    end_time = quiet_hours_end

    if start_time < end_time
      # Same day quiet hours (e.g., 22:00 to 23:00)
      current_time >= start_time && current_time <= end_time
    else
      # Overnight quiet hours (e.g., 22:00 to 08:00)
      current_time >= start_time || current_time <= end_time
    end
  end

  # Get enabled delivery channels
  def enabled_channels
    channels = []
    channels << :email if email_notifications?
    channels << :sms if sms_notifications?
    channels << :push if push_notifications?
    channels
  end

  # Check if immediate notifications are enabled
  def immediate_notifications?
    notification_frequency == "immediate" && !in_quiet_hours?
  end

  # Check if digest notifications are enabled
  def digest_notifications?
    %w[daily_digest weekly_digest].include?(notification_frequency)
  end

  # Check if all notifications are disabled
  def notifications_disabled?
    notification_frequency == "disabled"
  end
end
