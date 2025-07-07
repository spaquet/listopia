# app/services/invitation_service.rb
class InvitationService
  def initialize(invitable, inviter)
    @invitable = invitable
    @inviter = inviter
  end

  def invite(email, permission)
    existing_user = User.find_by(email: email)

    if existing_user
      add_existing_user(existing_user, permission)
    else
      invite_new_user(email, permission)
    end
  end

  def resend(invitation)
    invitation.update!(
      invitation_token: invitation.generate_invitation_token,
      invitation_sent_at: Time.current
    )

    InvitationMailer.invitation_reminder(invitation).deliver_later

    OpenStruct.new(success?: true, message: "Invitation resent successfully!")
  end

  private

  def add_existing_user(user, permission)
    return failure("Cannot invite the owner") if owner?(user)

    collaborator = @invitable.collaborators.find_or_initialize_by(user: user)

    if collaborator.persisted?
      if collaborator.update(permission: permission)
        success("#{user.name}'s permission updated")
      else
        failure(collaborator.errors.full_messages)
      end
    else
      collaborator.permission = permission
      if collaborator.save
        CollaborationMailer.added_to_resource(collaborator).deliver_later
        success("#{user.name} added as collaborator")
      else
        failure(collaborator.errors.full_messages)
      end
    end
  end

  def invite_new_user(email, permission)
    return failure("Cannot invite the owner") if owner_email?(email)

    invitation = @invitable.invitations.build(
      email: email,
      permission: permission,
      invited_by: @inviter
    )

    if invitation.save
      InvitationMailer.invitation(invitation).deliver_later
      success("Invitation sent to #{email}")
    else
      failure(invitation.errors.full_messages)
    end
  end

  def owner?(user)
    case @invitable
    when List
      @invitable.owner == user
    when ListItem
      @invitable.list.owner == user
    else
      false
    end
  end

  def owner_email?(email)
    case @invitable
    when List
      @invitable.owner.email == email
    when ListItem
      @invitable.list.owner.email == email
    else
      false
    end
  end

  def success(message)
    OpenStruct.new(success?: true, message: message)
  end

  def failure(errors)
    OpenStruct.new(success?: false, errors: Array(errors))
  end
end
