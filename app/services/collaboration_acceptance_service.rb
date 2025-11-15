# app/services/collaboration_acceptance_service.rb
#
# Purpose: Handle invitation acceptance flow for collaboration invitations
#
# This service manages the complex process of accepting a collaboration invitation:
# 1. Validates the invitation and user
# 2. Creates a Collaborator record with appropriate permissions
# 3. Grants optional roles (e.g., can_invite_collaborators)
# 4. Updates the invitation status
# 5. Sends notifications
#
# Usage:
#   service = CollaborationAcceptanceService.new(invitation)
#   result = service.accept(accepting_user)
#
#   if result.success?
#     redirect_to result.resource
#   else
#     flash[:alert] = result.errors.join(", ")
#   end

class CollaborationAcceptanceService
  def initialize(invitation)
    @invitation = invitation
  end

  def accept(accepting_user)
    return failure("Invalid or expired invitation") unless @invitation
    return failure("Invitation already accepted") if @invitation.accepted?

    # Verify email match
    unless accepting_user.email == @invitation.email
      return failure("Email mismatch. This invitation is for #{@invitation.email}")
    end

    ActiveRecord::Base.transaction do
      # Create collaborator
      collaborator = @invitation.invitable.collaborators.create!(
        user: accepting_user,
        permission: @invitation.permission
      )

      # Grant roles if specified in granted_roles array
      if @invitation.granted_roles.present?
        @invitation.granted_roles.each do |role_name|
          # Only grant roles that start with 'can_' for security
          if role_name.to_s.start_with?("can_")
            collaborator.add_role(role_name.to_sym)
          end
        end
      end

      # Mark invitation as accepted
      @invitation.update!(
        user: accepting_user,
        invitation_accepted_at: Time.current,
        status: "accepted"
      )

      # Log the acceptance for audit trail
      Rails.logger.info({
        event: "invitation_accepted",
        invitation_id: @invitation.id,
        resource_type: @invitation.invitable_type,
        resource_id: @invitation.invitable_id,
        user_id: accepting_user.id,
        acceptance_time_hours: (Time.current - @invitation.invitation_sent_at) / 1.hour
      }.to_json)

      success(
        collaborator: collaborator,
        resource: @invitation.invitable,
        message: "You've successfully joined #{@invitation.invitable.title}!"
      )
    end
  rescue ActiveRecord::RecordInvalid => e
    failure(e.record.errors.full_messages)
  rescue StandardError => e
    Rails.logger.error("Collaboration acceptance failed: #{e.message}")
    failure("An error occurred while accepting the invitation. Please try again.")
  end

  private

  def success(data)
    OpenStruct.new(success?: true, **data)
  end

  def failure(errors)
    OpenStruct.new(success?: false, errors: Array(errors))
  end
end
