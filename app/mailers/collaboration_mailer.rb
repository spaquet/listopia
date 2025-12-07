# app/mailers/collaboration_mailer.rb
class CollaborationMailer < ApplicationMailer
  default from: "noreply@listopia.com"

  def invitation(invitation)
    @invitation = invitation
    @invitable = invitation.invitable
    @invited_by = invitation.invited_by
    @invitation_url = accept_invitation_url(token: @invitation.generate_token_for(:invitation))
    @inviter_name = @invited_by&.name || "Someone"

    subject = "#{@inviter_name} invited you to collaborate on #{@invitable.title}"

    mail(
      to: @invitation.email,
      subject: subject
    )
  end

  def invitation_reminder(invitation)
    @invitation = invitation
    @invitable = invitation.invitable
    @invited_by = invitation.invited_by
    @inviter = @invited_by
    @inviter_name = @invited_by&.name || "Someone"
    @invitation_url = accept_invitation_url(token: @invitation.generate_token_for(:invitation))

    # Set @list for the template (handles both List and ListItem invitables)
    @list = case @invitable
    when ListItem
      @invitable.list
    else
      @invitable
    end

    # Generate URLs for the template
    @accept_url = @invitation_url
    @signup_url = new_registration_url

    mail(
      to: @invitation.email,
      subject: "Reminder: Invitation to collaborate on #{@invitable.title}"
    )
  end

  def added_to_resource(collaborator)
    @collaborator = collaborator
    @collaboratable = collaborator.collaboratable
    @resource_url = polymorphic_url(@collaboratable)

    mail(
      to: @collaborator.user.email,
      subject: "You've been added as a collaborator on #{@collaboratable.title}"
    )
  end

  def removed_from_resource(user, collaboratable)
    @user = user
    @collaboratable = collaboratable

    mail(
      to: @user.email,
      subject: "You've been removed from #{@collaboratable.title}"
    )
  end

  def permission_updated(collaborator, old_permission)
    @collaborator = collaborator
    @collaboratable = collaborator.collaboratable
    @old_permission = old_permission
    @new_permission = collaborator.permission
    @resource_url = polymorphic_url(@collaboratable)

    mail(
      to: @collaborator.user.email,
      subject: "Your permission has been updated for #{@collaboratable.title}"
    )
  end

  # Organization invitation for existing user
  def organization_invitation(membership_or_invitation)
    case membership_or_invitation
    when OrganizationMembership
      handle_organization_membership_email(membership_or_invitation)
    when Invitation
      handle_organization_invitation_email(membership_or_invitation)
    end
  end

  # Team member invitation for existing user or new invitee
  def team_member_invitation(membership_or_invitation)
    case membership_or_invitation
    when TeamMembership
      handle_team_membership_email(membership_or_invitation)
    when Invitation
      handle_team_invitation_email(membership_or_invitation)
    end
  end

  private

  def handle_organization_membership_email(membership)
    @membership = membership
    @organization = membership.organization
    @user = membership.user
    @inviter = @organization.creator
    @inviter_name = @inviter&.name || "Someone"
    @organization_url = organization_url(@organization)

    mail(
      to: @user.email,
      subject: "#{@inviter_name} added you to #{@organization.name}"
    )
  end

  def handle_organization_invitation_email(invitation)
    @invitation = invitation
    @organization = invitation.organization
    @email = invitation.email
    @inviter = invitation.invited_by
    @inviter_name = @inviter&.name || "Someone"
    @invitation_token = @invitation.generate_token_for(:invitation)
    @signup_url = new_registration_url
    @accept_url = accept_organization_invitation_url(token: @invitation_token)

    mail(
      to: @email,
      subject: "#{@inviter_name} invited you to join #{@organization.name}"
    )
  end

  def handle_team_membership_email(membership)
    @membership = membership
    @team = membership.team
    @organization = @team.organization
    @user = membership.user
    @inviter = @team.creator
    @inviter_name = @inviter&.name || "Someone"
    @team_url = organization_team_url(@organization, @team)
    @team_name = @team.name
    @organization_name = @organization.name

    mail(
      to: @user.email,
      subject: "#{@inviter_name} added you to team '#{@team.name}' in #{@organization.name}"
    )
  end

  def handle_team_invitation_email(invitation)
    @invitation = invitation
    @team = invitation.invitable
    @organization = invitation.organization
    @email = invitation.email
    @inviter = invitation.invited_by
    @inviter_name = @inviter&.name || "Someone"
    @invitation_token = @invitation.generate_token_for(:invitation)
    @signup_url = new_registration_url
    @accept_url = accept_invitation_url(token: @invitation_token)
    @team_name = @team.name
    @organization_name = @organization.name

    mail(
      to: @email,
      subject: "#{@inviter_name} invited you to join team '#{@team_name}' in #{@organization_name}"
    )
  end
end
