# app/notifiers/team_invitation_notifier.rb
class TeamInvitationNotifier < ApplicationNotifier
  def notification_type
    "team_invitation"
  end

  def title
    "Team invitation"
  end

  def message
    "#{actor_name} invited you to join the #{params[:team_name]} team"
  end

  def icon
    "users"
  end

  def url
    # Link to the team or organizations page
    organization_path(params[:organization_id])
  end
end
