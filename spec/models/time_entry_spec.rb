# == Schema Information
#
# Table name: time_entries
#
#  id           :uuid             not null, primary key
#  duration     :decimal(10, 2)   default(0.0), not null
#  ended_at     :datetime
#  metadata     :json
#  notes        :text
#  started_at   :datetime         not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  list_item_id :uuid             not null
#  user_id      :uuid             not null
#
require 'rails_helper'

RSpec.describe TimeEntry, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
