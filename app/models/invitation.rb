# == Schema Information
#
# Table name: invitations
#
#  id                     :uuid             not null, primary key
#  email                  :string
#  invitable_type         :string           not null
#  invitation_accepted_at :datetime
#  invitation_sent_at     :datetime
#  invitation_token       :string
#  permission             :integer          default("read"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  invitable_id           :uuid             not null
#  invited_by_id          :uuid
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

  scope :pending, -> { where(user_id: nil) }
  scope :accepted, -> { where.not(user_id: nil) }

  before_create :generate_invitation_token
  before_create :set_invitation_sent_at

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

  def accept!(accepting_user)
    return false unless accepting_user.email == email

    # Create collaborator record
    collaborator = invitable.collaborators.create!(
      user: accepting_user,
      permission: permission
    )

    # Update invitation
    update!(
      user: accepting_user,
      invitation_accepted_at: Time.current
    )

    collaborator
  end

  def generate_invitation_token
    self.invitation_token = generate_token_for(:invitation)
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
      # Add similar logic for list items
    end
  end

  def set_invitation_sent_at
    self.invitation_sent_at = Time.current
  end
end
