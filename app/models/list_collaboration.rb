# app/models/list_collaboration.rb
class ListCollaboration < ApplicationRecord
  # Rails 8 token generation for invitations
  generates_token_for :invitation, expires_in: 24.hours

  belongs_to :list
  belongs_to :user, optional: true

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
end
