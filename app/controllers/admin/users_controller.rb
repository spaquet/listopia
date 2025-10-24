# app/controllers/admin/users_controller.rb
class Admin::UsersController < Admin::BaseController
  # Admin::BaseController already has:
  # - authenticate_user!
  # - require_admin!
  # - layout "admin"

  before_action :set_user, only: %i[show edit update destroy toggle_admin toggle_status]

  # Allow Turbo Stream requests for these actions (disable CSRF only for these)
  skip_forgery_protection only: [ :toggle_admin, :toggle_status, :destroy ]

  helper_method :locale_options, :timezone_options

  def index
    authorize User

    # Initialize the filter service with params
    @filter_service = UserFilterService.new(
      query: params[:query],
      status: params[:status],
      role: params[:role],
      verified: params[:verified],
      sort_by: params[:sort_by]
    )

    # Get filtered users
    @users = @filter_service.filtered_users.includes(:roles).limit(100)

    # Store filters for view
    @filters = {
      query: params[:query],
      status: params[:status],
      role: params[:role],
      verified: params[:verified],
      sort_by: params[:sort_by]
    }

    # Respond to both HTML and Turbo Stream
    respond_to do |format|
      format.html
      format.turbo_stream do
        render turbo_stream: [
          # Update ONLY the users list container
          turbo_stream.replace("users-table", partial: "users_list", locals: { users: @users }),
          # Update the results summary with count
          turbo_stream.replace("results-summary", partial: "results_summary", locals: { users_count: @users.count })
        ]
      end
    end
  rescue => e
    Rails.logger.error("User filter error: #{e.message}\n#{e.backtrace.join("\n")}")
    flash.now[:alert] = "An error occurred while filtering users"
    render :index, status: :unprocessable_entity
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
    @user.email_verified_at = Time.current
    authorize @user, :create?

    if @user.save
      @user.add_role(:admin) if params[:user][:make_admin] == "1"

      respond_to do |format|
        format.html { redirect_to admin_user_path(@user), notice: "User created successfully." }
        format.turbo_stream do
          redirect_to admin_users_path, status: :see_other
        end
      end
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
      respond_to do |format|
        format.html { redirect_to admin_user_path(@user), notice: "User updated successfully." }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("user_#{@user.id}",
            partial: "user_row", locals: { user: @user, current_user: current_user })
        end
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @user, :destroy?

    if @user == current_user
      respond_to do |format|
        format.html { redirect_to admin_users_path, alert: "You cannot delete your own account." }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("user_#{@user.id}",
            partial: "user_row", locals: { user: @user, current_user: current_user }),
            status: :unprocessable_entity
        end
      end
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
      respond_to do |format|
        format.html { redirect_to admin_users_path, alert: "Failed to delete user." }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("user_#{@user.id}",
            partial: "user_row", locals: { user: @user, current_user: current_user }),
            status: :unprocessable_entity
        end
      end
    end
  end

  def toggle_admin
    authorize @user, :toggle_admin?

    if @user == current_user
      respond_to do |format|
        format.html { redirect_to admin_users_path, alert: "You cannot modify your own admin status." }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("user_#{@user.id}",
            partial: "user_row", locals: { user: @user, current_user: current_user }),
            status: :unprocessable_entity
        end
      end
      return
    end

    # Toggle admin role
    if @user.admin?
      @user.remove_role(:admin)
      message = "Admin privileges revoked."
    else
      @user.add_role(:admin)
      message = "Admin privileges granted."
    end

    respond_to do |format|
      format.html { redirect_to admin_users_path, notice: message }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("user_#{@user.id}",
          partial: "user_row", locals: { user: @user, current_user: current_user })
      end
    end
  end

  def toggle_status
    authorize @user, :toggle_status?

    if @user == current_user
      respond_to do |format|
        format.html { redirect_to admin_users_path, alert: "You cannot suspend your own account." }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("user_#{@user.id}",
            partial: "user_row", locals: { user: @user, current_user: current_user }),
            status: :unprocessable_entity
        end
      end
      return
    end

    # Toggle user status
    case @user.status
    when "active"
      @user.suspend!(reason: params[:reason], suspended_by: current_user)
      message = "User suspended successfully."
    when "suspended"
      @user.unsuspend!(unsuspended_by: current_user)
      message = "User reactivated successfully."
    end

    respond_to do |format|
      format.html { redirect_to admin_users_path, notice: message }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("user_#{@user.id}",
          partial: "user_row", locals: { user: @user, current_user: current_user })
      end
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_users_path, alert: "User not found."
  end

  def user_params
    params.require(:user).permit(:name, :email, :bio, :avatar_url, :locale, :timezone, :admin_notes)
  end

  def locale_options
    [ [ "English", "en" ], [ "Français", "fr" ], [ "Español", "es" ], [ "Deutsch", "de" ] ]
  end

  def timezone_options
    ActiveSupport::TimeZone.all.map { |tz| [ tz.to_s, tz.name ] }
  end
end
