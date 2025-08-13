# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :request_id, :user_agent, :ip_address
end
