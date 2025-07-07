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
FactoryBot.define do
  factory :time_entry do
    
  end
end
