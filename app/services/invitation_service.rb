# app/services/invitation_service.rb
require 'ostruct'

class InvitationService
  def initialize(invitable, inviter)
    @invitable = invitable
    @inviter = inviter
  end

  def invite(email, permission, grant_roles = {})
    existing_user = User.find_by(email: email)

    if existing_user
      add_existing_user(existing_user, permission, grant_roles)
    else
      invite_new_user(email, permission, grant_roles)
    end
  end

  def resend(invitation)
    invitation.update!(
      invitation_token: invitation.generate_invitation_token,
      invitation_sent_at: Time.current
    )

    CollaborationMailer.invitation_reminder(invitation).deliver_later

    OpenStruct.new(success?: true, message: "Invitation resent successfully!")
  end

  private

  def grant_optional_roles(collaborator, roles = {})
    # Skip role granting for now - to be implemented when needed
    # roles.each do |role_name, grant|
    #   # Only grant roles that start with 'can_' for security
    #   if grant && role_name.to_s.match?(/^can_/)
    #     collaborator.add_role(role_name.to_sym) unless collaborator.has_role?(role_name.to_sym)
    #   elsif !grant && role_name.to_s.match?(/^can_/)
    #     # Remove role if it was unchecked
    #     collaborator.remove_role(role_name.to_sym) if collaborator.has_role?(role_name.to_sym)
    #   end
    # end
  end

  def add_existing_user(user, permission, grant_roles = {})
    return failure("Cannot invite the owner") if owner?(user)

    collaborator = @invitable.collaborators.find_or_initialize_by(user: user)

    if collaborator.persisted?
      # Update existing collaborator
      old_permission = collaborator.permission
      if collaborator.update(permission: permission)
        grant_optional_roles(collaborator, grant_roles)
        CollaborationMailer.permission_updated(collaborator, old_permission).deliver_later if old_permission != collaborator.permission
        success("#{user.name}'s permission updated")
      else
        failure(collaborator.errors.full_messages)
      end
    else
      # Create new collaborator
      collaborator.permission = permission
      if collaborator.save
        grant_optional_roles(collaborator, grant_roles)
        CollaborationMailer.added_to_resource(collaborator).deliver_later
        send_collaboration_notification(user, collaborator)
        success("#{user.name} added as collaborator")
      else
        failure(collaborator.errors.full_messages)
      end
    end
  end

  def invite_new_user(email, permission, grant_roles = {})
    return failure("Cannot invite the owner") if owner_email?(email)

    # Convert grant_roles hash to array of role names that should be granted
    roles_to_grant = grant_roles.select { |_, grant| grant }.keys.map(&:to_s)

    invitation = @invitable.invitations.build(
      email: email,
      permission: permission,
      invited_by: @inviter,
      granted_roles: roles_to_grant
    )

    if invitation.save
      CollaborationMailer.invitation(invitation).deliver_later
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

  def send_collaboration_notification(user, collaborator)
    case @invitable
    when List
      ListCollaborationNotifier.with(
        actor_id: @inviter.id,
        list_id: @invitable.id
      ).deliver(user)
    when ListItem
      ListItemCollaborationNotifier.with(
        actor_id: @inviter.id,
        list_item_id: @invitable.id,
        list_id: @invitable.list.id
      ).deliver(user)
    end
  end

  def send_permission_updated_notification(user, collaborator)
    case @invitable
    when List
      ListCollaborationNotifier.with(
        actor_id: @inviter.id,
        list_id: @invitable.id
      ).deliver(user)
    when ListItem
      ListItemCollaborationNotifier.with(
        actor_id: @inviter.id,
        list_item_id: @invitable.id,
        list_id: @invitable.list.id
      ).deliver(user)
    end
  end
end
