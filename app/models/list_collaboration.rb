# app/models/list_collaboration.rb
# == Schema Information
#
# Table name: list_collaborations
#
#  id                     :uuid             not null, primary key
#  email                  :string
#  invitation_accepted_at :datetime
#  invitation_sent_at     :datetime
#  invitation_token       :string
#  permission             :integer          default("read"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  invited_by_id          :uuid
#  list_id                :uuid             not null
#  user_id                :uuid
#
# Indexes
#
#  index_list_collaborations_on_email                   (email)
#  index_list_collaborations_on_invitation_token        (invitation_token) UNIQUE
#  index_list_collaborations_on_invited_by_id           (invited_by_id)
#  index_list_collaborations_on_list_and_email          (list_id,email) UNIQUE WHERE (email IS NOT NULL)
#  index_list_collaborations_on_list_and_user           (list_id,user_id) UNIQUE WHERE (user_id IS NOT NULL)
#  index_list_collaborations_on_list_id                 (list_id)
#  index_list_collaborations_on_permission              (permission)
#  index_list_collaborations_on_user_id                 (user_id)
#  index_list_collaborations_on_user_id_and_permission  (user_id,permission)
#
# Foreign Keys
#
#  fk_rails_...  (invited_by_id => users.id)
#  fk_rails_...  (list_id => lists.id)
#  fk_rails_...  (user_id => users.id)
#
class ListCollaboration < ApplicationRecord
  # Rails 8 token generation for invitations
  generates_token_for :invitation, expires_in: 24.hours

  # Notifications
  after_create :notify_collaboration_added

  # Associations
  belongs_to :list
  belongs_to :user, optional: true  # Make user optional for pending invitations

  # Validations
  validates :email, presence: true, unless: :user_id?
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :permission, presence: true
  validates :user_id, uniqueness: { scope: :list_id }, allow_nil: true
  validates :email, uniqueness: { scope: :list_id }, allow_nil: true

  # Enums matching your existing schema
  enum :permission, {
    read: 0,
    collaborate: 1
  }, prefix: true

  validate :email_or_user_present
  validate :not_list_owner
  validate :email_not_already_user, on: :create

  scope :pending, -> { where(user_id: nil) }
  scope :accepted, -> { where.not(user_id: nil) }
  scope :readers, -> { where(permission: :read) }
  scope :collaborators, -> { where(permission: :collaborate) }

  def pending?
    user_id.nil?
  end

  def accepted?
    user_id.present?
  end

  def display_email
    user&.email || email
  end

  def display_name
    user&.name || user&.email || email
  end

  def can_edit?
    permission_collaborate?
  end

  def can_view?
    true # All collaborators can view
  end

  # Generate invitation token using Rails 8 method
  def generate_invitation_token
    generate_token_for(:invitation)
  end

  # Find collaboration by valid invitation token
  def self.find_by_invitation_token(token)
    find_by_token_for(:invitation, token)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  private

  def email_or_user_present
    if user_id.blank? && email.blank?
      errors.add(:base, "Either user or email must be present")
    end
  end

  def not_list_owner
    if user_id.present? && user_id == list&.user_id
      errors.add(:user, "cannot be the list owner")
    end

    if email.present? && email == list&.owner&.email
      errors.add(:email, "cannot be the list owner's email")
    end
  end

  def email_not_already_user
    return unless email.present?

    existing_user = User.find_by(email: email)
    if existing_user
      # Check if this user is already a collaborator
      existing_collaboration = list.list_collaborations.find_by(user: existing_user)
      if existing_collaboration
        errors.add(:email, "is already a collaborator on this list")
      end
    end
  end

  # Notify the owner when a new collaboration is created
  def notify_collaboration_added
    return unless Current.user

    ListCollaborationInviteNotifier.deliver_to_enabled_users([ user ], actor_id: Current.user.id, list_id: list.id)
  end
end
