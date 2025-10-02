# == Schema Information
#
# Table name: list_items
#
#  id                  :uuid             not null, primary key
#  description         :text
#  due_date            :datetime
#  duration_days       :integer          default(0), not null
#  estimated_duration  :decimal(10, 2)   default(0.0), not null
#  item_type           :integer          default("task"), not null
#  metadata            :json
#  position            :integer          default(0)
#  priority            :integer          default("medium"), not null
#  recurrence_end_date :datetime
#  recurrence_rule     :string           default("none"), not null
#  reminder_at         :datetime
#  skip_notifications  :boolean          default(FALSE), not null
#  start_date          :datetime         not null
#  status              :integer          default("pending"), not null
#  status_changed_at   :datetime
#  title               :string           not null
#  total_tracked_time  :decimal(10, 2)   default(0.0), not null
#  url                 :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  assigned_user_id    :uuid
#  board_column_id     :uuid
#  list_id             :uuid             not null
#
# Indexes
#
#  index_list_items_on_assigned_user_id             (assigned_user_id)
#  index_list_items_on_assigned_user_id_and_status  (assigned_user_id,status)
#  index_list_items_on_board_column_id              (board_column_id)
#  index_list_items_on_created_at                   (created_at)
#  index_list_items_on_due_date                     (due_date)
#  index_list_items_on_due_date_and_status          (due_date,status)
#  index_list_items_on_item_type                    (item_type)
#  index_list_items_on_list_id                      (list_id)
#  index_list_items_on_list_id_and_position         (list_id,position) UNIQUE
#  index_list_items_on_list_id_and_priority         (list_id,priority)
#  index_list_items_on_list_id_and_status           (list_id,status)
#  index_list_items_on_position                     (position)
#  index_list_items_on_priority                     (priority)
#  index_list_items_on_skip_notifications           (skip_notifications)
#  index_list_items_on_status                       (status)
#
# Foreign Keys
#
#  fk_rails_...  (assigned_user_id => users.id)
#  fk_rails_...  (board_column_id => board_columns.id)
#  fk_rails_...  (list_id => lists.id)
#
require "test_helper"

class ListItemTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
