# app/models/user.rb
# == Schema Information
#
# Table name: users
#
#  id                       :uuid             not null, primary key
#  avatar_url               :string
#  bio                      :text
#  email                    :string           not null
#  email_verification_token :string
#  email_verified_at        :datetime
#  locale                   :string(10)       default("en"), not null
#  name                     :string           not null
#  password_digest          :string           not null
#  provider                 :string
#  timezone                 :string(50)       default("UTC"), not null
#  uid                      :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
# Indexes
#
#  index_users_on_email                     (email) UNIQUE
#  index_users_on_email_verification_token  (email_verification_token) UNIQUE
#  index_users_on_locale                    (locale)
#  index_users_on_provider_and_uid          (provider,uid) UNIQUE
#  index_users_on_timezone                  (timezone)
#
class User < ApplicationRecord
  rolify
  has_secure_password

  # Rails 8 token generation for magic links and email verification
  generates_token_for :magic_link, expires_in: 15.minutes
  generates_token_for :email_verification, expires_in: 24.hours

  # Core associations
  has_many :lists, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_many :chats, dependent: :destroy
  has_many :messages, dependent: :destroy

  # Collaboration associations
  has_many :time_entries, dependent: :destroy
  has_many :collaborators, dependent: :destroy
  has_many :collaborated_lists, through: :collaborators, source: :collaboratable, source_type: "List"
  has_many :collaborated_list_items, through: :collaborators, source: :collaboratable, source_type: "ListItem"
  has_many :invitations, dependent: :destroy
  has_many :sent_invitations, class_name: "Invitation", foreign_key: "invited_by_id"
  has_many :received_invitations, class_name: "Invitation", foreign_key: "user_id"
  has_many :comments, dependent: :destroy

  # Notification associations
  has_many :notifications, as: :recipient, dependent: :destroy, class_name: "Noticed::Notification"
  has_one :notification_settings, class_name: "NotificationSetting", dependent: :destroy

  # Validations
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true

  # Callbacks
  before_validation :set_defaults, on: :create
  after_create :create_default_notification_settings

  # Scopes
  scope :verified, -> { where.not(email_verified_at: nil) }

  # Notification methods
  def notification_preferences
    notification_settings || create_default_notification_settings
  end

  def wants_notification?(notification_type, channel = :email)
    settings = notification_preferences
    return false if settings.notifications_disabled?
    return false unless settings.notifications_enabled_for?(notification_type)

    case channel.to_sym
    when :email
      settings.email_notifications?
    when :sms
      settings.sms_notifications?
    when :push
      settings.push_notifications?
    else
      false
    end
  end

  def unread_notifications_count
    notifications.where(read_at: nil).count
  end

  def unseen_notifications_count
    notifications.where(seen_at: nil).count
  end

  # Email verification methods
  def email_verified?
    email_verified_at.present?
  end

  def verify_email!
    update!(email_verified_at: Time.current)
  end

  # Magic link and token methods
  def generate_magic_link_token
    generate_token_for(:magic_link)
  end

  def generate_email_verification_token
    token = generate_token_for(:email_verification)
    self.email_verification_token = token
    save!
    token
  end

  def self.find_by_magic_link_token(token)
    find_by_token_for(:magic_link, token)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  def self.find_by_email_verification_token(token)
    find_by_token_for(:email_verification, token)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  # List access methods
  def accessible_lists
    owned_list_ids = lists.pluck(:id)
    collaborated_list_ids = collaborated_lists.pluck(:id)
    public_list_ids = List.where(is_public: true).pluck(:id)

    all_accessible_ids = (owned_list_ids + collaborated_list_ids + public_list_ids).uniq
    List.where(id: all_accessible_ids)
  end

  # Simplified current_chat method - let RubyLLM handle the complexity
  def current_chat
    chats.where(status: "active")
         .order(last_message_at: :desc, created_at: :desc)
         .first_or_create!(
           title: "Chat #{Time.current.strftime('%m/%d %H:%M')}",
           model_id: Rails.application.config.mcp&.model || "gpt-4.1-nano"
         )
  end

  # I18n helper
  def with_locale(&block)
    I18n.with_locale(locale, &block)
  end

  private

  def set_defaults
    self.locale ||= I18n.default_locale.to_s
    self.timezone ||= "UTC"
  end

  def create_default_notification_settings
    build_notification_settings.save! unless notification_settings
    notification_settings
  end
end
