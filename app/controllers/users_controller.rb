# app/controllers/users_controller.rb
class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_current_user, only: [ :show, :edit, :update, :settings, :update_password, :update_preferences, :update_notification_settings ]
  before_action :set_admin_user, only: [ :suspend, :unsuspend, :deactivate, :reactivate, :grant_admin, :revoke_admin, :update_admin_notes, :destroy ]
  before_action :authorize_action, only: [ :settings, :update_password, :update_preferences, :update_notification_settings ]

  helper_method :locale_options, :timezone_options

  # User profile view
  def show
    # @user already set by before_action
    authorize @user
  end

  def edit
    # @user already set by before_action
    authorize @user
  end

  def update
    authorize @user

    allowed_params = user_params.select do |key, _|
      UserPolicy.new(current_user, @user).permitted_attributes.include?(key.to_sym)
    end

    if @user.update(allowed_params)
      redirect_to profile_path, notice: "Profile updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Settings page - users can only access their own settings
  def settings
    # @user already set by before_action and authorized
  end

  def update_password
    # @user already set and authorized by before_action
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
    # @user already set and authorized by before_action
    if @user.update(preference_params)
      redirect_to settings_user_path, notice: "Preferences updated successfully."
    else
      flash.now[:alert] = "Failed to update preferences."
      render :settings, status: :unprocessable_entity
    end
  end

  def update_notification_settings
    # @user already set and authorized by before_action
    notification_settings = @user.notification_preferences

    if notification_settings.update(notification_settings_params)
      redirect_to settings_user_path, notice: "Notification preferences updated successfully."
    else
      flash.now[:alert] = "Failed to update notification preferences."
      render :settings, status: :unprocessable_entity
    end
  end

  # Admin actions
  def index
    authorize User
    @pagy, @users = pagy(policy_scope(User).order(created_at: :desc))
  end

  def suspend
    authorize @user
    @user.suspend!(reason: params[:reason], suspended_by: current_user)
    respond_to do |format|
      format.html { redirect_to admin_user_path(@user), notice: "User suspended successfully." }
      format.turbo_stream { render :suspended }
    end
  end

  def unsuspend
    authorize @user
    @user.unsuspend!(unsuspended_by: current_user)
    respond_to do |format|
      format.html { redirect_to admin_user_path(@user), notice: "User unsuspended successfully." }
      format.turbo_stream { render :unsuspended }
    end
  end

  def deactivate
    authorize @user
    @user.deactivate!(reason: params[:reason], deactivated_by: current_user)
    respond_to do |format|
      format.html { redirect_to admin_user_path(@user), notice: "User deactivated successfully." }
      format.turbo_stream { render :deactivated }
    end
  end

  def reactivate
    authorize @user
    @user.reactivate!(reactivated_by: current_user)
    respond_to do |format|
      format.html { redirect_to admin_user_path(@user), notice: "User reactivated successfully." }
      format.turbo_stream { render :reactivated }
    end
  end

  def grant_admin
    authorize @user
    @user.make_admin!
    respond_to do |format|
      format.html { redirect_to admin_user_path(@user), notice: "Admin privileges granted." }
      format.turbo_stream { render :admin_granted }
    end
  end

  def revoke_admin
    authorize @user
    @user.remove_admin!
    respond_to do |format|
      format.html { redirect_to admin_user_path(@user), notice: "Admin privileges revoked." }
      format.turbo_stream { render :admin_revoked }
    end
  end

  def update_admin_notes
    authorize @user
    @user.update_admin_notes!(params[:notes], updated_by: current_user)
    respond_to do |format|
      format.html { redirect_to admin_user_path(@user), notice: "Admin notes updated." }
      format.turbo_stream { render :admin_notes_updated }
    end
  end

  def destroy
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
  end

  def set_admin_user
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to users_path, alert: "User not found."
  end

  def authorize_action
    action_method = "#{action_name}?".to_sym
    policy = UserPolicy.new(current_user, @user)

    unless policy.public_send(action_method)
      raise Pundit::NotAuthorizedError, policy: policy, query: action_method
    end
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
