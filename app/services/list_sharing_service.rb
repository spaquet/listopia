# app/services/list_sharing_service.rb
class ListSharingService < ApplicationService
  # Service to handle complex list sharing operations
  # Manages permissions, invitations, and access control

  def initialize(list, current_user)
    @list = list
    @current_user = current_user
  end

  def call
    # This service can be extended for complex sharing logic
    yield self if block_given?
  end

  # Share list with a user via email
  def share_with_email(email, permission: "read", send_notification: true)
    return failure(errors: "Not authorized") unless can_manage_sharing?

    user = User.find_by(email: email)

    if user
      add_existing_user(user, permission, send_notification)
    else
      invite_new_user(email, permission)
    end
  end

  # Generate public sharing link
  def generate_public_link
    return failure(errors: "Not authorized") unless can_manage_sharing?

    if @list.public_slug.blank?
      @list.update!(
        public_slug: SecureRandom.urlsafe_base64(8),
        is_public: true
      )
    end

    success(data: {
      public_url: public_list_url,
      direct_url: list_url(@list)
    })
  end

  # Revoke public access
  def revoke_public_access
    return failure(errors: "Not authorized") unless can_manage_sharing?

    @list.update!(is_public: false, public_slug: nil)
    success(message: "Public access revoked")
  end

  # Remove collaborator
  def remove_collaborator(user_or_email)
    return failure(errors: "Not authorized") unless can_manage_sharing?

    user = user_or_email.is_a?(String) ? User.find_by(email: user_or_email) : user_or_email
    return failure(errors: "User not found") unless user

    collaboration = @list.list_collaborations.find_by(user: user)
    return failure(errors: "User is not a collaborator") unless collaboration

    collaboration.destroy

    # Send notification
    CollaborationMailer.removed_from_list(user, @list).deliver_later if user.email_verified?

    success(message: "#{user.name} removed from list")
  end

  # Update collaborator permission
  def update_permission(user, new_permission)
    return failure(errors: "Not authorized") unless can_manage_sharing?

    collaboration = @list.list_collaborations.find_by(user: user)
    return failure(errors: "User is not a collaborator") unless collaboration

    if collaboration.update(permission: new_permission)
      success(data: collaboration, message: "Permission updated")
    else
      failure(errors: collaboration.errors.full_messages)
    end
  end

  # Get sharing summary
  def sharing_summary
    {
      is_public: @list.is_public?,
      public_url: @list.is_public? ? public_list_url : nil,
      direct_url: list_url(@list),
      collaborators_count: @list.list_collaborations.count,
      read_only_collaborators: @list.list_collaborations.permission_read.count,
      full_collaborators: @list.list_collaborations.permission_collaborate.count
    }
  end

  private

  # Check if current user can manage sharing for this list
  def can_manage_sharing?
    @list.owner == @current_user
  end

  # Add existing user as collaborator
  def add_existing_user(user, permission, send_notification)
    return failure(errors: "Cannot add list owner as collaborator") if user == @list.owner

    collaboration = @list.list_collaborations.find_or_initialize_by(user: user)

    if collaboration.persisted?
      # Update existing collaboration
      if collaboration.update(permission: permission)
        send_collaboration_notification(collaboration) if send_notification
        success(data: collaboration, message: "#{user.name}'s permission updated")
      else
        failure(errors: collaboration.errors.full_messages)
      end
    else
      # Create new collaboration
      collaboration.permission = permission
      if collaboration.save
        send_collaboration_notification(collaboration) if send_notification
        success(data: collaboration, message: "#{user.name} added to list")
      else
        failure(errors: collaboration.errors.full_messages)
      end
    end
  end

  # Invite new user (not yet registered)
  def invite_new_user(email, permission)
    invitation_token = SecureRandom.urlsafe_base64(32)

    # Store invitation temporarily
    Rails.cache.write(
      "invitation_#{invitation_token}",
      {
        email: email,
        list_id: @list.id,
        permission: permission,
        invited_by: @current_user.id,
        invited_at: Time.current
      },
      expires_in: 7.days
    )

    # Send invitation email
    CollaborationMailer.invitation(email, @list, @current_user, invitation_token).deliver_later

    success(message: "Invitation sent to #{email}")
  end

  # Send notification about collaboration
  def send_collaboration_notification(collaboration)
    if collaboration.user.email_verified?
      CollaborationMailer.added_to_list(collaboration).deliver_later
    end
  end

  # Generate public list URL using the pretty slug
  def public_list_url
    return nil unless @list.public_slug.present?
    Rails.application.routes.url_helpers.public_list_url(@list.public_slug)
  end

  # Generate direct list URL using the ID
  def list_url(list)
    Rails.application.routes.url_helpers.list_url(list)
  end
end
