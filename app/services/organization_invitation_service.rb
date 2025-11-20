# app/services/organization_invitation_service.rb
class OrganizationInvitationService
  def initialize(organization, invited_by, emails, role = "member")
    @organization = organization
    @invited_by = invited_by
    @emails = parse_emails(emails)
    @role = role
    @results = { created: [], already_member: [], invalid: [] }
  end

  def invite_users
    @emails.each do |email|
      email = email.strip.downcase
      next if email.blank?

      begin
        process_email(email)
      rescue StandardError => e
        @results[:invalid] << { email: email, error: e.message }
      end
    end

    @results
  end

  private

  def parse_emails(emails)
    case emails
    when String
      # Split by comma and newline
      emails.split(/[,\n]/).map(&:strip).reject(&:blank?)
    when Array
      emails.map(&:strip).reject(&:blank?)
    else
      []
    end
  end

  def process_email(email)
    # Validate email format
    unless email.match?(URI::MailTo::EMAIL_REGEXP)
      @results[:invalid] << { email: email, error: "Invalid email format" }
      return
    end

    user = User.find_by(email: email)

    if user.present?
      # User already exists - check if already member
      if @organization.organization_memberships.exists?(user: user)
        @results[:already_member] << { email: email, user_id: user.id, name: user.name }
      else
        # Add existing user as member
        membership = create_membership(user)
        @results[:created] << { email: email, user_id: user.id, name: user.name, type: "existing_user" }
        # Send welcome email to existing user
        CollaborationMailer.organization_invitation(membership).deliver_later
      end
    else
      # User doesn't exist - create invitation
      invitation = create_invitation(email)
      @results[:created] << { email: email, invitation_id: invitation.id, type: "invitation" }
      # Send invitation email
      CollaborationMailer.organization_invitation(invitation).deliver_later
    end
  end

  def create_membership(user)
    OrganizationMembership.create!(
      organization: @organization,
      user: user,
      role: @role,
      status: :active,
      joined_at: Time.current
    )
  end

  def create_invitation(email)
    Invitation.create!(
      organization: @organization,
      email: email,
      invited_by: @invited_by,
      invitable_type: "Organization",
      invitable_id: @organization.id,
      permission: :read,
      status: "pending",
      metadata: { role: @role }
    )
  end
end
