# spec/factories/sessions.rb
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
FactoryBot.define do
  factory :session do
    sequence(:session_token) { |n| SecureRandom.urlsafe_base64(32) }
    ip_address { "192.168.1.1" }
    user_agent { "Mozilla/5.0 (X11; Linux x86_64)" }
    expires_at { 30.days.from_now }
    association :user
  end
end
