# app/controllers/users_controller.rb
class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user, only: [ :show, :edit, :update, :destroy ]
  before_action :authorize_user!, only: [ :show, :edit, :update, :destroy ]

  # Make helper methods available to views
  helper_method :locale_options, :timezone_options

  # List users (admin only)
  def index
    authorize User
    @pagy, @users = pagy(policy_scope(User).order(created_at: :desc))
  end

  def show
    # User profile view
  end

  def edit
    # Edit profile form
  end

  def update
    # Filter params based on policy
    allowed_params = user_params.select do |key, _|
      UserPolicy.new(current_user, @user).permitted_attributes.include?(key.to_sym)
    end

    if @user.update(allowed_params)
      redirect_to user_path(@user), notice: "Profile updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Admin actions
  def destroy
    authorize @user

    if @user.destroy
      redirect_to users_path, notice: "User deleted successfully."
    else
      redirect_to users_path, alert: "Failed to delete user."
    end
  end

  # Settings page
  def settings
    @user = current_user
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

  # Admin user management actions
  def suspend
    authorize @user

    @user.suspend!(
      reason: params[:reason],
      suspended_by: current_user
    )

    respond_to do |format|
      format.html { redirect_to @user, notice: "User suspended successfully." }
      format.turbo_stream { render :suspended }
    end
  end

  def unsuspend
    authorize @user

    @user.unsuspend!(unsuspended_by: current_user)

    respond_to do |format|
      format.html { redirect_to @user, notice: "User unsuspended successfully." }
      format.turbo_stream { render :unsuspended }
    end
  end

  def deactivate
    authorize @user

    @user.deactivate!(
      reason: params[:reason],
      deactivated_by: current_user
    )

    respond_to do |format|
      format.html { redirect_to @user, notice: "User deactivated successfully." }
      format.turbo_stream { render :deactivated }
    end
  end

  def reactivate
    authorize @user

    @user.reactivate!(reactivated_by: current_user)

    respond_to do |format|
      format.html { redirect_to @user, notice: "User reactivated successfully." }
      format.turbo_stream { render :reactivated }
    end
  end

  def grant_admin
    authorize @user, :grant_admin?

    @user.make_admin!

    respond_to do |format|
      format.html { redirect_to @user, notice: "Admin privileges granted." }
      format.turbo_stream { render :admin_updated }
    end
  end

  def revoke_admin
    authorize @user, :revoke_admin?

    @user.remove_admin!

    respond_to do |format|
      format.html { redirect_to @user, notice: "Admin privileges revoked." }
      format.turbo_stream { render :admin_updated }
    end
  end

  def update_admin_notes
    authorize @user, :update_admin_notes?

    @user.update_admin_notes!(params[:notes], updated_by: current_user)

    respond_to do |format|
      format.html { redirect_to @user, notice: "Admin notes updated." }
      format.turbo_stream { render :notes_updated }
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to users_path, alert: "User not found."
  end

  def authorize_user!
    authorize @user
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
    [
      [ "English", "en" ],
      [ "Français", "fr" ],
      [ "Español", "es" ],
      [ "Deutsch", "de" ]
    ]
  end

  def timezone_options
    ActiveSupport::TimeZone.all.map { |tz| [ tz.to_s, tz.name ] }
  end
end
