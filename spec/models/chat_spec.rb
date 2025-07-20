# == Schema Information
#
# Table name: chats
#
#  id              :uuid             not null, primary key
#  context         :json
#  last_message_at :datetime
#  last_stable_at  :datetime
#  metadata        :json
#  status          :string           default("active")
#  title           :string(255)
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  model_id        :string
#  user_id         :uuid             not null
#
# Indexes
#
#  index_chats_on_last_message_at         (last_message_at)
#  index_chats_on_last_stable_at          (last_stable_at)
#  index_chats_on_model_id                (model_id)
#  index_chats_on_user_id                 (user_id)
#  index_chats_on_user_id_and_created_at  (user_id,created_at)
#  index_chats_on_user_id_and_status      (user_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require 'rails_helper'

RSpec.describe Chat, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
