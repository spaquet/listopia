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
require 'rails_helper'

RSpec.describe NotificationSetting, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
