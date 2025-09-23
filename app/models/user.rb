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
# Update app/models/user.rb - Add notification association and methods
class User < ApplicationRecord
  rolify
  has_secure_password

  # Rails 8 token generation for magic links and email verification
  generates_token_for :magic_link, expires_in: 15.minutes
  generates_token_for :email_verification, expires_in: 24.hours

  # Associations
  has_many :lists, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_many :chats, dependent: :destroy
  has_many :messages, dependent: :destroy

  has_many :time_entries, dependent: :destroy
  has_many :collaborators, dependent: :destroy
  has_many :collaborated_lists, through: :collaborators, source: :collaboratable, source_type: "List"
  has_many :collaborated_list_items, through: :collaborators, source: :collaboratable, source_type: "ListItem"
  has_many :conversation_contexts, dependent: :destroy
  has_many :invitations, dependent: :destroy
  has_many :sent_invitations, class_name: "Invitation", foreign_key: "invited_by_id"
  has_many :received_invitations, class_name: "Invitation", foreign_key: "user_id"
  has_many :comments, dependent: :destroy

  # Add noticed notifications
  has_many :notifications, as: :recipient, dependent: :destroy, class_name: "Noticed::Notification"

  # Notification settings
  has_one :notification_settings, class_name: "NotificationSetting", dependent: :destroy

  # Validations
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true

  # Callbacks
  before_validation :set_defaults, on: :create
  after_create :create_default_notification_settings

  # Scopes
  scope :verified, -> { where.not(email_verified_at: nil) }

  # Methods

  # Get notification settings (with fallback)
  def notification_preferences
    notification_settings || create_default_notification_settings
  end

  # Check if user wants notifications for a specific type and channel
  def wants_notification?(notification_type, channel = :email)
    settings = notification_preferences

    # Check if notifications are disabled entirely
    return false if settings.notifications_disabled?

    # Check if this notification type is enabled
    return false unless settings.notifications_enabled_for?(notification_type)

    # Check if this channel is enabled
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

  # Check if user wants immediate notifications
  def wants_immediate_notifications?
    notification_preferences.immediate_notifications?
  end

  # Used to reset the current chat
  def reset_current_chat!
    # Archive the current chat
    current_chat&.update!(status: "archived")

    # Create a fresh chat
    chats.create!(
      status: "active",
      title: "Chat #{Time.current.strftime('%m/%d %H:%M')}"
    )
  end

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
    owned_list_ids = lists.pluck(:id)
    collaborated_list_ids = collaborated_lists.pluck(:id)
    public_list_ids = List.where(is_public: true).pluck(:id)

    all_accessible_ids = (owned_list_ids + collaborated_list_ids + public_list_ids).uniq

    List.where(id: all_accessible_ids)
  end

  # Notification convenience methods
  def unread_notifications_count
    notifications.where(read_at: nil).count
  end

  def unseen_notifications_count
    notifications.where(seen_at: nil).count
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

  # Get or create the active chat for this user
  def current_chat
    chats.status_active.recent.first || chats.create!(
      status: "active",
      title: "Chat #{Time.current.strftime('%m/%d %H:%M')}",
      conversation_state: "stable",
      last_stable_at: Time.current
    )
  end

  # Get chat history summary
  def chat_summary
    {
      total_chats: chats.count,
      total_messages: messages.count,
      total_tokens: chats.sum { |chat| chat.total_tokens },
      last_chat_at: chats.maximum(:last_message_at)
    }
  end

  # Helper method to get recent context
  def recent_conversation_contexts(limit: 20)
    conversation_contexts
      .active
      .recent
      .limit(limit)
      .includes(:chat)
  end

  # Get context for specific entity type
  def contexts_for_entity_type(entity_type, limit: 10)
    conversation_contexts
      .for_entity_type(entity_type)
      .active
      .recent
      .limit(limit)
  end

  # Get most recent list context
  def current_list_context
    contexts_for_entity_type("List", limit: 1).first
  end

  # Check if user has recent activity
  def has_recent_activity?(hours: 1)
    conversation_contexts.within_timeframe(hours).exists?
  end

  # Set locale for I18n around user actions
  def with_locale(&block)
    I18n.with_locale(locale, &block)
  end

  # Get user's preferred locale or fallback to default
  def preferred_locale
    locale.presence&.to_sym || I18n.default_locale
  end

  # Timezone-aware methods
  def in_timezone(&block)
    Time.use_zone(timezone, &block)
  end

  def current_time
    Time.current.in_time_zone(timezone)
  end

  # Private methods
  private

  # Set default locale and timezone on user creation
  def set_defaults
    self.locale ||= I18n.default_locale.to_s
    self.timezone ||= "UTC"
  end

  def create_default_notification_settings
    build_notification_settings.save! unless notification_settings
    notification_settings
  end
end
