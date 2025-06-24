# app/models/session.rb
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
class Session < ApplicationRecord
  belongs_to :user

  validates :session_token, presence: true, uniqueness: true
  validates :ip_address, presence: true
  validates :user_agent, presence: true

  scope :active, -> { where("expires_at > ?", Time.current) }
  scope :expired, -> { where("expires_at <= ?", Time.current) }

  before_create :generate_session_token, :set_expiry

  # Find session by token
  def self.find_by_token(token)
    active.find_by(session_token: token)
  end

  # Check if session is active
  def active?
    expires_at > Time.current
  end

  # Extend session expiry
  def extend_expiry!
    update!(expires_at: 30.days.from_now)
  end

  # Revoke session
  def revoke!
    update!(expires_at: Time.current)
  end

  private

  def generate_session_token
    self.session_token = SecureRandom.urlsafe_base64(32)
  end

  def set_expiry
    self.expires_at = 30.days.from_now
  end
end
