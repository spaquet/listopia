# spec/factories/sessions.rb
FactoryBot.define do
  factory :session do
    sequence(:session_token) { |n| SecureRandom.urlsafe_base64(32) }
    ip_address { "192.168.1.1" }
    user_agent { "Mozilla/5.0 (X11; Linux x86_64)" }
    expires_at { 30.days.from_now }
    association :user
  end
end
