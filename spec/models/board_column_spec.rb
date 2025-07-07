# == Schema Information
#
# Table name: board_columns
#
#  id         :uuid             not null, primary key
#  metadata   :json
#  name       :string           not null
#  position   :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  list_id    :uuid             not null
#
# Indexes
#
#  index_board_columns_on_list_id  (list_id)
#
# Foreign Keys
#
#  fk_rails_...  (list_id => lists.id)
#
require 'rails_helper'

RSpec.describe BoardColumn, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
