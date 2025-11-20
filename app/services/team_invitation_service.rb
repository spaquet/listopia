# app/services/team_invitation_service.rb
class TeamInvitationService
  def initialize(team, invited_by, emails, role = "member")
    @team = team
    @organization = team.organization
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
      # User exists - check if already in team
      if @team.users.exists?(user)
        @results[:already_member] << { email: email, user_id: user.id, name: user.name }
      else
        # Check if user is in organization
        org_membership = @organization.membership_for(user)
        unless org_membership
          @results[:invalid] << { email: email, error: "User is not a member of this organization" }
          return
        end

        # Add existing user to team
        membership = create_team_membership(user, org_membership)
        @results[:created] << { email: email, user_id: user.id, name: user.name, type: "existing_user" }
        # Send notification email
        CollaborationMailer.team_member_invitation(membership).deliver_later
      end
    else
      # User doesn't exist - create invitation
      invitation = create_team_invitation(email)
      @results[:created] << { email: email, invitation_id: invitation.id, type: "invitation" }
      # Send invitation email
      CollaborationMailer.team_member_invitation(invitation).deliver_later
    end
  end

  def create_team_membership(user, org_membership)
    TeamMembership.create!(
      team: @team,
      user: user,
      organization_membership: org_membership,
      role: @role
    )
  end

  def create_team_invitation(email)
    Invitation.create!(
      organization: @organization,
      email: email,
      invited_by: @invited_by,
      invitable_type: "Team",
      invitable_id: @team.id,
      permission: :read,
      status: "pending",
      metadata: { role: @role, team_id: @team.id }
    )
  end
end
