# app/models/user.rb
class User < ApplicationRecord
  has_secure_password

  # Rails 8 token generation for magic links and email verification
  generates_token_for :magic_link, expires_in: 15.minutes
  generates_token_for :email_verification, expires_in: 24.hours

  # Associations
  has_many :lists, dependent: :destroy
  has_many :list_collaborations, dependent: :destroy
  has_many :collaborated_lists, through: :list_collaborations, source: :list
  has_many :sessions, dependent: :destroy

  # Validations
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true

  # Scopes
  scope :verified, -> { where.not(email_verified_at: nil) }

  # Methods

  # Check if user's email is verified
  def email_verified?
    email_verified_at.present?
  end

  # Mark email as verified
  def verify_email!
    update!(email_verified_at: Time.current)
  end

  # Get all accessible lists (owned + collaborated)
  def accessible_lists
    List.where(id: lists.pluck(:id) + collaborated_lists.pluck(:id))
  end

  # Generate magic link token (using Rails 8 generates_token_for)
  def generate_magic_link_token
    generate_token_for(:magic_link)
  end

  # Generate email verification token (using Rails 8 generates_token_for)
  def generate_email_verification_token
    token = generate_token_for(:email_verification)
    self.email_verification_token = token
    save!
    token
  end

  # Find user by valid magic link token
  def self.find_by_magic_link_token(token)
    find_by_token_for(:magic_link, token)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  # Find user by valid email verification token
  def self.find_by_email_verification_token(token)
    find_by_token_for(:email_verification, token)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end
end
