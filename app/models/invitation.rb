# == Schema Information
#
# Table name: invitations
#
#  id                     :uuid             not null, primary key
#  email                  :string
#  granted_roles          :string           default([]), not null, is an Array
#  invitable_type         :string           not null
#  invitation_accepted_at :datetime
#  invitation_expires_at  :datetime
#  invitation_sent_at     :datetime
#  invitation_token       :string
#  message                :text
#  metadata               :jsonb            not null
#  permission             :integer          default("read"), not null
#  status                 :string           default("pending"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  invitable_id           :uuid             not null
#  invited_by_id          :uuid
#  organization_id        :uuid
#  user_id                :uuid
#
# Indexes
#
#  index_invitations_on_email                (email)
#  index_invitations_on_invitable            (invitable_type,invitable_id)
#  index_invitations_on_invitable_and_email  (invitable_id,invitable_type,email) UNIQUE WHERE (email IS NOT NULL)
#  index_invitations_on_invitable_and_user   (invitable_id,invitable_type,user_id) UNIQUE WHERE (user_id IS NOT NULL)
#  index_invitations_on_invitation_token     (invitation_token) UNIQUE
#  index_invitations_on_invited_by_id        (invited_by_id)
#  index_invitations_on_organization_id      (organization_id)
#  index_invitations_on_status               (status)
#  index_invitations_on_user_id              (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (invited_by_id => users.id)
#  fk_rails_...  (user_id => users.id)
#

# app/models/invitation.rb
class Invitation < ApplicationRecord
  belongs_to :invitable, polymorphic: true
  belongs_to :user, optional: true
  belongs_to :invited_by, class_name: "User"
  belongs_to :organization, optional: true

  # Rails 8 token generation
  generates_token_for :invitation, expires_in: 7.days

  enum :permission, {
    read: 0,
    write: 1
  }, prefix: true

  validates :email, presence: true, unless: :user_id?
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :permission, presence: true
  validates :user_id, uniqueness: { scope: [ :invitable_type, :invitable_id ] }, allow_nil: true
  validates :email, uniqueness: { scope: [ :invitable_type, :invitable_id ] }, allow_nil: true

  validate :email_or_user_present
  validate :not_owner

  scope :pending, -> { where(status: "pending") }
  scope :accepted, -> { where(status: "accepted") }
  scope :expired, -> { where(status: "expired") }

  before_create :set_invitation_sent_at
  before_validation :set_default_status, on: :create
  before_save :clear_invitation_token

  def pending?
    status == "pending"
  end

  def accepted?
    status == "accepted"
  end

  def expired?
    status == "expired"
  end

  def display_email
    user&.email || email
  end

  def display_name
    user&.name || user&.email || email
  end

  def accept!(accepting_user)
    return false unless accepting_user.email == email

    ActiveRecord::Base.transaction do
      # Create collaborator record
      collaborator = invitable.collaborators.create!(
        user: accepting_user,
        permission: permission
      )

      # Grant roles if specified
      if granted_roles.present?
        granted_roles.each do |role_name|
          if role_name.to_s.start_with?("can_")
            collaborator.add_role(role_name.to_sym)
          end
        end
      end

      # Update invitation
      update!(
        user: accepting_user,
        invitation_accepted_at: Time.current,
        status: "accepted"
      )

      collaborator
    end
  end

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

  def not_owner
    case invitable_type
    when "List"
      if user_id.present? && user_id == invitable&.user_id
        errors.add(:user, "cannot be the list owner")
      end

      if email.present? && email == invitable&.owner&.email
        errors.add(:email, "cannot be the list owner's email")
      end
    when "ListItem"
      list = invitable&.list
      if list.present?
        if user_id.present? && user_id == list.user_id
          errors.add(:user, "cannot be the list owner")
        end

        if email.present? && email == list.owner&.email
          errors.add(:email, "cannot be the list owner's email")
        end
      end
    end
  end

  def set_invitation_sent_at
    self.invitation_sent_at = Time.current
  end

  def set_default_status
    self.status ||= "pending"
  end

  def clear_invitation_token
    self.invitation_token = nil
  end
end
