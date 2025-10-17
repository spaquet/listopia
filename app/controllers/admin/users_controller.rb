# app/controllers/admin/users_controller.rb
class Admin::UsersController < Admin::BaseController
  before_action :authenticate_user!
  before_action :set_user, only: [ :show, :edit, :update, :destroy, :toggle_admin, :toggle_status ]

  helper_method :locale_options, :timezone_options

  def index
    @pagy, @users = pagy(User.includes(:roles).order(created_at: :desc))
  end

  def show
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    @user.email_verified_at = Time.current # Auto-verify admin-created users

    if @user.save
      @user.add_role(:admin) if params[:user][:make_admin] == "1"
      redirect_to admin_user_path(@user), notice: "User created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @user.update(user_params)
      redirect_to admin_user_path(@user), notice: "User updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @user == current_user
      redirect_to admin_users_path, alert: "You cannot delete your own account."
      return
    end

    @user.destroy
    redirect_to admin_users_path, notice: "User deleted successfully."
  end

  def toggle_admin
    if @user == current_user
      redirect_to admin_user_path(@user), alert: "You cannot modify your own admin status."
      return
    end

    if @user.admin?
      @user.remove_role(:admin)
      message = "Admin privileges revoked."
    else
      @user.add_role(:admin)
      message = "Admin privileges granted."
    end

    redirect_to admin_user_path(@user), notice: message
  end

  def toggle_status
    if @user == current_user
      redirect_to admin_user_path(@user), alert: "You cannot suspend your own account."
      return
    end

    case @user.status
    when "active"
      @user.suspend!(reason: params[:reason], suspended_by: current_user)
      message = "User suspended successfully."
    when "suspended"
      @user.unsuspend!(unsuspended_by: current_user)
      message = "User reactivated successfully."
    end

    redirect_to admin_user_path(@user), notice: message
  end

  private

  def set_user
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_users_path, alert: "User not found."
  end

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation, :bio, :locale, :timezone, :admin_notes)
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
