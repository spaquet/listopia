# == Schema Information
#
# Table name: list_items
#
#  id                 :uuid             not null, primary key
#  completed          :boolean          default(FALSE)
#  completed_at       :datetime
#  description        :text
#  due_date           :datetime
#  item_type          :integer          default("task"), not null
#  metadata           :json
#  position           :integer          default(0)
#  priority           :integer          default("medium"), not null
#  reminder_at        :datetime
#  skip_notifications :boolean          default(FALSE), not null
#  title              :string           not null
#  url                :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  assigned_user_id   :uuid
#  list_id            :uuid             not null
#
# Indexes
#
#  index_list_items_on_assigned_user_id                (assigned_user_id)
#  index_list_items_on_assigned_user_id_and_completed  (assigned_user_id,completed)
#  index_list_items_on_completed                       (completed)
#  index_list_items_on_created_at                      (created_at)
#  index_list_items_on_due_date                        (due_date)
#  index_list_items_on_due_date_and_completed          (due_date,completed)
#  index_list_items_on_item_type                       (item_type)
#  index_list_items_on_list_id                         (list_id)
#  index_list_items_on_list_id_and_completed           (list_id,completed)
#  index_list_items_on_list_id_and_position            (list_id,position) UNIQUE
#  index_list_items_on_list_id_and_priority            (list_id,priority)
#  index_list_items_on_position                        (position)
#  index_list_items_on_priority                        (priority)
#  index_list_items_on_skip_notifications              (skip_notifications)
#
# Foreign Keys
#
#  fk_rails_...  (assigned_user_id => users.id)
#  fk_rails_...  (list_id => lists.id)
#
require "test_helper"

class ListItemTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
