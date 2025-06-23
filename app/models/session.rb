# app/models/session.rb
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
