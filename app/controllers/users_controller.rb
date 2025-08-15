# app/controllers/users_controller.rb
class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user, only: [ :show, :edit, :update ]
  before_action :authorize_user_access!, only: [ :edit, :update ]


  # Make helper methods available to views - THIS GOES AT THE TOP
  helper_method :locale_options, :timezone_options

  def show; end

  def edit; end

  def update
    if @user.update(user_params)
      redirect_to user_path, notice: "Profile updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def settings
    @user = current_user
    # Ensure notification settings exist - this is the key fix!
    @user.notification_preferences
  end

  def update_password
    @user = current_user
    if @user.authenticate(params[:current_password])
      if @user.update(password_params)
        redirect_to settings_user_path, notice: "Password updated successfully."
      else
        flash.now[:alert] = "Password update failed."
        render :settings, status: :unprocessable_entity
      end
    else
      flash.now[:alert] = "Current password is incorrect."
      render :settings, status: :unprocessable_entity
    end
  end

  def update_preferences
    @user = current_user
    if @user.update(preference_params)
      redirect_to settings_user_path, notice: "Preferences updated successfully."
    else
      flash.now[:alert] = "Failed to update preferences."
      render :settings, status: :unprocessable_entity
    end
  end

  # Update the user's notification settings
  def update_notification_settings
    @user = current_user
    notification_settings = @user.notification_preferences

    if notification_settings.update(notification_settings_params)
      redirect_to settings_user_path, notice: "Notification preferences updated successfully."
    else
      flash.now[:alert] = "Failed to update notification preferences."
      render :settings, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :bio, :avatar_url, :locale, :timezone)
  end

  def password_params
    params.require(:user).permit(:password, :password_confirmation)
  end

  def preference_params
    params.require(:user).permit(:email_notifications, :theme_preference)
  end

  def notification_settings_params
    params.require(:notification_settings).permit(
      :email_notifications,
      :sms_notifications,
      :push_notifications,
      :collaboration_notifications,
      :list_activity_notifications,
      :item_activity_notifications,
      :status_change_notifications,
      :notification_frequency
    )
  end

  def set_user
    @user = User.find(params[:id])
  end

  # TODO: Upgrade this to use Pundit and Rolify for authorization
  def authorize_user_access!
    unless @user == current_user
      redirect_to root_path, alert: "Access denied."
    end
  end

  # Helper methods for locale and timezone dropdowns
  def locale_options
    [
      [ "English", "en" ],
      [ "Español", "es" ],
      [ "Français", "fr" ],
      [ "Deutsch", "de" ],
      [ "日本語", "ja" ],
      [ "中文", "zh" ],
      [ "العربية", "ar" ],
      [ "Русский", "ru" ],
      [ "Português", "pt" ],
      [ "Italiano", "it" ]
    ]
  end

  def timezone_options
    ActiveSupport::TimeZone.all.map { |tz| [ tz.to_s, tz.name ] }
  end
end
