# app/controllers/users_controller.rb
class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_current_user, only: [ :show, :edit, :update, :settings, :update_password, :update_preferences, :update_notification_settings ]

  helper_method :locale_options, :timezone_options

  # User profile view
  def show
    # @user already set by before_action
  end

  def edit
    # @user already set by before_action
    render :edit
  end

  def update
    allowed_params = user_params.select do |key, _|
      UserPolicy.new(current_user, @user).permitted_attributes.include?(key.to_sym)
    end

    if @user.update(allowed_params)
      redirect_to profile_path, notice: "Profile updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Settings page
  def settings
    # @user already set by before_action
  end

  def update_password
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
    if @user.update(preference_params)
      redirect_to settings_user_path, notice: "Preferences updated successfully."
    else
      flash.now[:alert] = "Failed to update preferences."
      render :settings, status: :unprocessable_entity
    end
  end

  def update_notification_settings
    notification_settings = @user.notification_preferences

    if notification_settings.update(notification_settings_params)
      redirect_to settings_user_path, notice: "Notification preferences updated successfully."
    else
      flash.now[:alert] = "Failed to update notification preferences."
      render :settings, status: :unprocessable_entity
    end
  end

  # Admin actions (keep these as-is for admin user management)
  def index
    authorize User
    @pagy, @users = pagy(policy_scope(User).order(created_at: :desc))
  end

  def suspend
    set_admin_user
    authorize @user

    @user.suspend!(reason: params[:reason], suspended_by: current_user)
    respond_to do |format|
      format.html { redirect_to admin_user_path(@user), notice: "User suspended successfully." }
      format.turbo_stream { render :suspended }
    end
  end

  def unsuspend
    set_admin_user
    authorize @user
    @user.unsuspend!(unsuspended_by: current_user)
    respond_to do |format|
      format.html { redirect_to admin_user_path(@user), notice: "User unsuspended successfully." }
      format.turbo_stream { render :unsuspended }
    end
  end

  def destroy
    set_admin_user
    authorize @user
    if @user.destroy
      redirect_to users_path, notice: "User deleted successfully."
    else
      redirect_to users_path, alert: "Failed to delete user."
    end
  end

  private

  def set_current_user
    @user = current_user
    authorize @user
  end

  def set_admin_user
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to users_path, alert: "User not found."
  end

  def user_params
    params.require(:user).permit(:name, :email, :bio, :avatar_url, :locale, :timezone, :admin_notes)
  end

  def password_params
    params.require(:user).permit(:password, :password_confirmation)
  end

  def preference_params
    params.require(:user).permit(:locale, :timezone)
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

  def locale_options
    [ [ "English", "en" ], [ "Français", "fr" ], [ "Español", "es" ], [ "Deutsch", "de" ] ]
  end

  def timezone_options
    ActiveSupport::TimeZone.all.map { |tz| [ tz.to_s, tz.name ] }
  end
end
