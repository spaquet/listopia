# == Schema Information
#
# Table name: sessions
#
#  id               :uuid             not null, primary key
#  expires_at       :datetime         not null
#  ip_address       :string
#  last_accessed_at :datetime
#  session_token    :string           not null
#  user_agent       :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  user_id          :uuid             not null
#
# Indexes
#
#  index_sessions_on_expires_at              (expires_at)
#  index_sessions_on_session_token           (session_token) UNIQUE
#  index_sessions_on_user_id                 (user_id)
#  index_sessions_on_user_id_and_expires_at  (user_id,expires_at)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require "test_helper"

class SessionTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
