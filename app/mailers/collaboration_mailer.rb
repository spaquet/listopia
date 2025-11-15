# app/mailers/collaboration_mailer.rb
class CollaborationMailer < ApplicationMailer
  default from: "noreply@listopia.com"

  def invitation(invitation)
    @invitation = invitation
    @invitable = invitation.invitable
    @invited_by = invitation.invited_by
    @invitation_url = accept_invitation_url(@invitation.invitation_token)
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
    @invitation_url = accept_invitation_url(@invitation.invitation_token)

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
end
