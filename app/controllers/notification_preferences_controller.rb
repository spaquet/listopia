# app/controllers/notification_preferences_controller.rb
class NotificationPreferencesController < ApplicationController
  before_action :authenticate_user!
  before_action :load_preferences

  def show
    @notification_types = notification_types_config
  end

  def update
    update_preferences_from_params
    render :show, notice: "Notification preferences updated successfully"
  end

  private

  def load_preferences
    @preferences = current_user.notification_settings || current_user.create_notification_settings
  end

  def update_preferences_from_params
    if params[:notification_preferences].present?
      params[:notification_preferences].each do |key, value|
        case key
        when "email_enabled"
          @preferences.update(email_enabled: value == "1")
        when "sms_enabled"
          @preferences.update(sms_enabled: value == "1")
        when "push_enabled"
          @preferences.update(push_enabled: value == "1")
        when "quiet_hours_enabled"
          @preferences.update(quiet_hours_enabled: value == "1")
        when "quiet_hours_start"
          @preferences.update(quiet_hours_start: value) if value.present?
        when "quiet_hours_end"
          @preferences.update(quiet_hours_end: value) if value.present?
        when "timezone"
          @preferences.update(timezone: value) if value.present?
        else
          # Handle individual notification type preferences
          update_notification_type_preference(key, value)
        end
      end
    end
  end

  def update_notification_type_preference(key, value)
    # Parse keys like "item_assignment_frequency" into type and channel
    parts = key.split("_")
    if parts.size >= 3
      frequency = parts[-1]
      type = parts[0..-2].join("_")

      if notification_types_config.keys.map(&:to_s).include?(type)
        preferences = @preferences.type_preferences ||= {}
        preferences[type] ||= {}
        preferences[type]["frequency"] = frequency
        @preferences.update(type_preferences: preferences)
      end
    end
  end

  def notification_types_config
    {
      item_assignment: { label: "Item Assignment", description: "When you're assigned a task" },
      item_comment: { label: "Item Comments", description: "When someone comments on items you're involved with" },
      item_completion: { label: "Item Completion", description: "When collaborators complete items" },
      item_priority_changed: { label: "Priority Changes", description: "When item priority is elevated to high/urgent" },
      permission_changed: { label: "Permission Changes", description: "When your access level changes" },
      team_invitation: { label: "Team Invitations", description: "When you're invited to a team" },
      list_archived: { label: "List Archived", description: "When a list you collaborate on is archived" },
      mention: { label: "Mentions", description: "When someone mentions you in comments" },
      collaboration: { label: "Collaboration", description: "When users are added/removed from lists" },
      list_activity: { label: "List Activity", description: "When list titles are updated" },
      item_activity: { label: "Item Activity", description: "When list items are created/updated/deleted" },
      status_change: { label: "Status Changes", description: "When list status changes" },
      digest: { label: "Digest", description: "Summary of your activity" }
    }
  end
end
