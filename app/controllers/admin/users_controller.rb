# app/controllers/admin/users_controller.rb
class Admin::UsersController < Admin::BaseController
  before_action :set_user, only: %i[show edit update destroy toggle_admin toggle_status]

  helper_method :locale_options, :timezone_options

  def index
    authorize User

    # Use ONLY params, no session fallback
    @filter_service = UserFilterService.new(
      query: params[:query],
      status: params[:status],
      role: params[:role],
      verified: params[:verified],
      sort_by: params[:sort_by]
    )

    @users = @filter_service.filtered_users.includes(:roles).limit(100)

    @filters = {
      query: @filter_service.query,
      status: @filter_service.status,
      role: @filter_service.role,
      verified: @filter_service.verified,
      sort_by: @filter_service.sort_by
    }

    @total_users = User.count

    respond_to do |format|
      format.html
      format.turbo_stream do
        render :index
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

    # Generate random password ONLY in admin controller
    # uses the generate_temp_password method from User model
    @user.generate_temp_password

    authorize @user, :create?

    if @user.save
      @user.add_role(:admin) if params[:user][:make_admin] == "1"
      @user.send_admin_invitation!
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
          render turbo_stream: turbo_stream.replace("user_#{@user.id}", "")
        end
      end
    else
      @user.destroy
      respond_to do |format|
        format.html { redirect_to admin_users_path, notice: "User deleted successfully." }
        format.turbo_stream do
          render turbo_stream: turbo_stream.remove("user_#{@user.id}")
        end
      end
    end
  end

  def toggle_status
    authorize @user, :toggle_status?

    if @user.status_active?
      @user.suspend!(reason: "Suspended by admin", suspended_by: current_user)
      message = "User suspended successfully."
    elsif @user.status_suspended?
      @user.unsuspend!(unsuspended_by: current_user)
      message = "User activated successfully."
    else
      message = "Cannot toggle status for users in #{@user.status} state."
    end

    respond_to do |format|
      format.html { redirect_to admin_users_path, notice: message }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("user_#{@user.id}",
          partial: "user_row", locals: { user: @user, current_user: current_user })
      end
    end
  end

  def toggle_admin
    authorize @user, :toggle_admin?

    if @user.admin?
      @user.remove_admin!
      message = "Admin privileges removed."
    else
      @user.make_admin!
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
