# app/controllers/notification_preferences_controller.rb
class NotificationPreferencesController < ApplicationController
  before_action :authenticate_user!
  before_action :load_preferences

  def show
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
      update_params = {}

      params[:notification_preferences].each do |key, value|
        case key
        when "email_notifications"
          update_params[:email_notifications] = value == "1"
        when "push_notifications"
          update_params[:push_notifications] = value == "1"
        when "sms_notifications"
          update_params[:sms_notifications] = value == "1"
        when "collaboration_notifications"
          update_params[:collaboration_notifications] = value == "1"
        when "list_activity_notifications"
          update_params[:list_activity_notifications] = value == "1"
        when "item_activity_notifications"
          update_params[:item_activity_notifications] = value == "1"
        when "status_change_notifications"
          update_params[:status_change_notifications] = value == "1"
        when "notification_frequency"
          update_params[:notification_frequency] = value if value.present?
        when "quiet_hours_start"
          update_params[:quiet_hours_start] = value if value.present?
        when "quiet_hours_end"
          update_params[:quiet_hours_end] = value if value.present?
        when "timezone"
          update_params[:timezone] = value if value.present?
        end
      end

      @preferences.update(update_params) if update_params.any?
    end
  end
end
