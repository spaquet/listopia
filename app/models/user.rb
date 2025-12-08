# app/models/user.rb
# == Schema Information
#
# Table name: users
#
#  id                       :uuid             not null, primary key
#  account_metadata         :jsonb
#  admin_notes              :text
#  avatar_url               :string
#  bio                      :text
#  deactivated_at           :datetime
#  deactivated_reason       :text
#  discarded_at             :datetime
#  email                    :string           not null
#  email_verification_token :string
#  email_verified_at        :datetime
#  invited_by_admin         :boolean          default(FALSE)
#  last_sign_in_at          :datetime
#  last_sign_in_ip          :string
#  locale                   :string(10)       default("en"), not null
#  name                     :string           not null
#  password_digest          :string           not null
#  provider                 :string
#  sign_in_count            :integer          default(0), not null
#  status                   :string           default("active"), not null
#  suspended_at             :datetime
#  suspended_reason         :text
#  timezone                 :string(50)       default("UTC"), not null
#  uid                      :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  current_organization_id  :uuid
#  suspended_by_id          :uuid
#
# Indexes
#
#  index_users_on_account_metadata          (account_metadata) USING gin
#  index_users_on_current_organization_id   (current_organization_id)
#  index_users_on_deactivated_at            (deactivated_at)
#  index_users_on_discarded_at              (discarded_at)
#  index_users_on_email                     (email) UNIQUE
#  index_users_on_email_verification_token  (email_verification_token) UNIQUE
#  index_users_on_invited_by_admin          (invited_by_admin)
#  index_users_on_last_sign_in_at           (last_sign_in_at)
#  index_users_on_locale                    (locale)
#  index_users_on_provider_and_uid          (provider,uid) UNIQUE
#  index_users_on_status                    (status)
#  index_users_on_suspended_at              (suspended_at)
#  index_users_on_timezone                  (timezone)
#
# Foreign Keys
#
#  fk_rails_...  (suspended_by_id => users.id)
#
class User < ApplicationRecord
  rolify
  has_secure_password

  # Logidzy for auditing changes
  has_logidze

  # Soft delete using Discard gem
  include Discard::Model

  # Rails 8 token generation for magic links and email verification
  generates_token_for :magic_link, expires_in: 15.minutes
  generates_token_for :email_verification, expires_in: 24.hours

  # Core associations
  has_many :lists, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_many :chats, dependent: :destroy
  has_many :messages, dependent: :destroy

  # Organization & Team associations
  has_many :organization_memberships, dependent: :destroy
  has_many :organizations, through: :organization_memberships
  has_many :team_memberships, dependent: :destroy
  has_many :teams, through: :team_memberships
  belongs_to :current_organization, class_name: "Organization", optional: true

  # Collaboration associations
  has_many :time_entries, dependent: :destroy
  has_many :collaborators, dependent: :destroy
  has_many :collaborated_lists, through: :collaborators, source: :collaboratable, source_type: "List"
  has_many :collaborated_list_items, through: :collaborators, source: :collaboratable, source_type: "ListItem"
  has_many :invitations, dependent: :destroy
  has_many :sent_invitations, class_name: "Invitation", foreign_key: "invited_by_id"
  has_many :received_invitations, class_name: "Invitation", foreign_key: "user_id"
  has_many :comments, dependent: :destroy

  # Association for suspension tracking
  belongs_to :suspended_by, class_name: "User", optional: true

  # Notification associations
  has_many :notifications, as: :recipient, dependent: :destroy, class_name: "Noticed::Notification"
  has_one :notification_settings, class_name: "NotificationSetting", dependent: :destroy

  # Validations
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true

  # Callbacks
  before_validation :set_defaults, on: :create
  after_create :create_default_notification_settings
  before_save :ensure_current_organization_is_valid

  # Scopes
  scope :verified, -> { where.not(email_verified_at: nil) }

  scope :admins, -> { with_role(:admin) }
  scope :active_users, -> { where(status: "active") }
  scope :suspended_users, -> { where(status: "suspended") }
  scope :deactivated_users, -> { where(status: "deactivated") }
  scope :recent_signins, -> { where.not(last_sign_in_at: nil).order(last_sign_in_at: :desc) }
  scope :search_by_email, ->(query) { where("email ILIKE ?", "%#{query}%") }
  scope :search_by_name, ->(query) { where("name ILIKE ?", "%#{query}%") }


  # Notification methods
  def notification_preferences
    notification_settings || create_default_notification_settings
  end

  # Status enum for user accounts
  enum :status, {
    active: "active",
    suspended: "suspended",
    deactivated: "deactivated",
    pending_verification: "pending_verification"
  }, prefix: true

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

  def wants_digest_notifications?(frequency = :daily)
    settings = notification_preferences
    return false if settings.notifications_disabled?

    digest_prefs = settings.type_preferences&.dig("digest") || {}
    digest_prefs["frequency"] == frequency.to_s
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
        .first
  end

  # I18n helper
  def with_locale(&block)
    I18n.with_locale(locale, &block)
  end

  # Organization methods
  def in_organization?(organization)
    organizations.exists?(organization.is_a?(Organization) ? organization.id : organization)
  end

  def organization_membership(organization)
    organization_memberships.find_by(organization: organization)
  end

  def organization_role(organization)
    organization_membership(organization)&.role
  end

  def organization_teams(organization)
    teams.joins(:team_memberships)
         .where(teams: { organization_id: organization.id })
         .distinct
  end

  # Admin role checks using Rolify
  def admin?
    has_role?(:admin)
  end

  def make_admin!
    add_role(:admin) unless admin?
  end

  def remove_admin!
    remove_role(:admin) if admin?
  end

  # Account status checks
  def active?
    status_active? && !suspended? && !deactivated?
  end

  def suspended?
    suspended_at.present? && status_suspended?
  end

  def deactivated?
    deactivated_at.present? && status_deactivated?
  end

  def can_sign_in?
    email_verified? && active?
  end

  # Suspend user account
  def suspend!(reason: nil, suspended_by: nil)
    transaction do
      update!(
        status: "suspended",
        suspended_at: Time.current,
        suspended_reason: reason,
        suspended_by: suspended_by
      )
      sessions.destroy_all
      log_admin_action("suspended", suspended_by, reason: reason)
    end
  end

  # Unsuspend user account
  def unsuspend!(unsuspended_by: nil)
    transaction do
      update!(
        status: "active",
        suspended_at: nil,
        suspended_reason: nil,
        suspended_by: nil
      )
      log_admin_action("unsuspended", unsuspended_by)
    end
  end

  # Deactivate user account
  def deactivate!(reason: nil, deactivated_by: nil)
    transaction do
      update!(
        status: "deactivated",
        deactivated_at: Time.current,
        deactivated_reason: reason
      )
      sessions.destroy_all
      log_admin_action("deactivated", deactivated_by, reason: reason)
    end
  end

  # Reactivate user account
  def reactivate!(reactivated_by: nil)
    transaction do
      update!(
        status: "active",
        deactivated_at: nil,
        deactivated_reason: nil
      )
      log_admin_action("reactivated", reactivated_by)
    end
  end

  # Update admin notes
  def update_admin_notes!(notes, updated_by: nil)
    update!(admin_notes: notes)
    log_admin_action("notes_updated", updated_by)
  end

  # Track user sign-in
  def track_sign_in!(ip_address: nil)
    increment!(:sign_in_count)
    update_columns(
      last_sign_in_at: Time.current,
      last_sign_in_ip: ip_address
    )
  end

  # Get comprehensive profile summary for AI context
  def profile_summary(include_sensitive: false)
    summary = {
      id: id,
      name: name,
      email: email,
      status: status,
      admin: admin?,
      email_verified: email_verified?,
      created_at: created_at,
      last_sign_in_at: last_sign_in_at,
      sign_in_count: sign_in_count,
      locale: locale,
      timezone: timezone,
      lists_count: lists.count,
      collaborations_count: collaborators.count
    }

    if include_sensitive && suspended?
      summary.merge!({
        suspended_at: suspended_at,
        suspended_reason: suspended_reason,
        suspended_by: suspended_by&.email
      })
    end

    if include_sensitive && deactivated?
      summary.merge!({
        deactivated_at: deactivated_at,
        deactivated_reason: deactivated_reason
      })
    end

    summary
  end

  # Get admin audit trail
  def admin_audit_trail
    return [] unless account_metadata.present?
    account_metadata["admin_actions"] || []
  end

  # User during user creation by an admin
  # either when the user is created via the chat or admin panel
  def generate_temp_password
    random_password = SecureRandom.hex(16)
    self.password = random_password
    self.password_confirmation = random_password
  end

  def send_admin_invitation!
    # Mark this user as admin-invited (not self-registered)
    self.invited_by_admin = true
    self.save!

    token = generate_email_verification_token
    AdminMailer.user_invitation(self, token).deliver_later
  end


  private

  def ensure_current_organization_is_valid
    # If current_organization_id is nil but user has organizations, set to first one
    if current_organization_id.nil? && organizations.any?
      self.current_organization_id = organizations.first.id
    end

    # If current_organization_id is set, verify it's actually a user's organization
    if current_organization_id.present? && !in_organization?(current_organization_id)
      self.current_organization_id = organizations.first&.id
    end
  end

  def set_defaults
    self.locale ||= I18n.default_locale.to_s
    self.timezone ||= "UTC"
  end

  def create_default_notification_settings
    build_notification_settings.save! unless notification_settings
    notification_settings
  end

  # Log admin actions to account metadata for audit trail
  def log_admin_action(action, performed_by, **details)
    metadata = account_metadata || {}
    metadata["admin_actions"] ||= []

    metadata["admin_actions"] << {
      action: action,
      performed_by_id: performed_by&.id,
      performed_by_email: performed_by&.email,
      performed_at: Time.current.iso8601,
      details: details.compact
    }

    # Keep only last 100 actions to prevent bloating
    metadata["admin_actions"] = metadata["admin_actions"].last(100)

    update_column(:account_metadata, metadata)
  end
end
