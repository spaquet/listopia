# app/controllers/admin/users_controller.rb
class Admin::UsersController < Admin::BaseController
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :set_user, only: %i[show edit update destroy toggle_admin toggle_status]

  # Allow button_to POST requests
  skip_forgery_protection only: [ :toggle_admin, :toggle_status ]

  helper_method :locale_options, :timezone_options

  def index
    authorize User

    # Initialize the filter service
    @filter_service = UserFilterService.new(
      query: params[:query],
      status: params[:status],
      role: params[:role],
      verified: params[:verified],
      sort_by: params[:sort_by]
    )

    # Get filtered users with simple limit for now (no pagy due to config issues)
    @users = @filter_service.filtered_users.includes(:roles).limit(100)

    # Store filters in instance for view
    @filters = {
      query: params[:query],
      status: params[:status],
      role: params[:role],
      verified: params[:verified],
      sort_by: params[:sort_by]
    }
  end

  def show
    authorize @user, :show?
  end

  def new
    @user = User.new
    authorize @user, :create?
  end

  def create
    @user = User.new(user_params)
    @user.email_verified_at = Time.current # Auto-verify admin-created users
    authorize @user, :create?

    if @user.save
      @user.add_role(:admin) if params[:user][:make_admin] == "1"
      redirect_to admin_user_path(@user), notice: "User created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @user, :edit?
  end

  def update
    authorize @user, :update?

    if @user.update(user_params)
      redirect_to admin_user_path(@user), notice: "User updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @user, :destroy?

    if @user == current_user
      redirect_to admin_users_path, alert: "You cannot delete your own account."
      return
    end

    if @user.destroy
      respond_to do |format|
        format.html { redirect_to admin_users_path, notice: "User deleted successfully." }
        format.turbo_stream do
          render turbo_stream: turbo_stream.remove("user_#{@user.id}")
        end
      end
    else
      redirect_to admin_users_path, alert: "Failed to delete user."
    end
  end

  def toggle_admin
    authorize @user, :toggle_admin?

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

    respond_to do |format|
      format.html { redirect_to admin_user_path(@user), notice: message }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("user_#{@user.id}",
          partial: "user_row", locals: { user: @user })
      end
    end
  end

  def toggle_status
    authorize @user, :toggle_status?

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

    respond_to do |format|
      format.html { redirect_to admin_user_path(@user), notice: message }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("user_#{@user.id}",
          partial: "user_row", locals: { user: @user })
      end
    end
  end

  def bulk_action
    authorize User, :index?

    user_ids = params[:user_ids]&.reject(&:blank?) || []
    action = params[:bulk_action]

    if user_ids.empty?
      redirect_to admin_users_path, alert: "Please select at least one user."
      return
    end

    service = BulkUserActionService.new(current_user, user_ids, action)

    if service.execute
      redirect_to admin_users_path, notice: service.message
    else
      redirect_to admin_users_path, alert: service.error_message
    end
  end

  private

  def authorize_admin!
    unless current_user&.admin?
      redirect_to root_path, alert: "You are not authorized to access this area."
    end
  end

  def set_user
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_users_path, alert: "User not found."
  end

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation, :status, :admin_notes, :locale, :timezone)
  end

  def locale_options
    [
      [ "English", "en" ],
      [ "Spanish", "es" ],
      [ "French", "fr" ],
      [ "German", "de" ],
      [ "Italian", "it" ],
      [ "Portuguese", "pt" ],
      [ "Dutch", "nl" ],
      [ "Polish", "pl" ],
      [ "Russian", "ru" ],
      [ "Chinese (Simplified)", "zh-CN" ],
      [ "Japanese", "ja" ],
      [ "Korean", "ko" ]
    ]
  end

  def timezone_options
    ActiveSupport::TimeZone.all.map { |tz| [ tz.to_s, tz.name ] }
  end
end
