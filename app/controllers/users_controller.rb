# app/controllers/users_controller.rb
class UsersController < ApplicationController
  before_action :authenticate_user!

  def show
    @user = current_user
  end

  def edit
    @user = current_user
  end

  def update
    @user = current_user
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
    params.require(:user).permit(:name, :email, :bio, :avatar_url)
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
end
