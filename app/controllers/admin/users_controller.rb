# app/controllers/admin/users_controller.rb
class Admin::UsersController < Admin::BaseController
  before_action :set_user, only: %i[show edit update destroy toggle_admin toggle_status resend_invitation]

  helper_method :locale_options, :timezone_options

  def index
    authorize User

    # Get current admin's organizations for filtering
    @admin_organizations = current_user.organizations.order(name: :asc)

    # Get organization_id from params (default to current_organization if admin has one)
    organization_id = params[:organization_id] || current_user.current_organization_id

    # Validate that the organization_id belongs to the admin
    if organization_id.present? && !current_user.in_organization?(organization_id)
      flash.now[:alert] = "You don't have access to that organization"
      organization_id = current_user.current_organization_id
    end

    # Use ONLY params, no session fallback
    @filter_service = UserFilterService.new(
      query: params[:query],
      status: params[:status],
      role: params[:role],
      verified: params[:verified],
      sort_by: params[:sort_by],
      organization_id: organization_id
    )

    @users = @filter_service.filtered_users.includes(:roles).limit(100)

    # Fetch pending invitations for the organization to show in the user list
    @pending_invitations = if organization_id.present?
      Invitation.where(
        organization_id: organization_id,
        invitable_type: "Organization",
        status: "pending",
        user_id: nil  # Only show invitations for users who haven't accepted yet
      ).order(created_at: :desc)
    else
      []
    end

    @filters = {
      query: @filter_service.query,
      status: @filter_service.status,
      role: @filter_service.role,
      verified: @filter_service.verified,
      sort_by: @filter_service.sort_by,
      organization_id: @filter_service.organization_id
    }

    # Count total users in selected organization if filtering by org
    @total_users = organization_id.present? ?
      User.joins(:organization_memberships)
          .where(organization_memberships: { organization_id: organization_id })
          .distinct
          .count + @pending_invitations.count :
      User.count

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

    # Store organization_id for creating user in specific organization
    @organization_id = params[:organization_id]

    # Validate organization access if provided
    if @organization_id.present? && !current_user.in_organization?(@organization_id)
      flash[:alert] = "You don't have access to that organization"
      redirect_to admin_users_path and return
    end
  end

  def create
    @user = User.new(user_params)

    # Generate random password ONLY in admin controller
    # uses the generate_temp_password method from User model
    @user.generate_temp_password

    # Set status to pending_verification until user accepts invitation
    @user.status = "pending_verification"

    authorize @user, :create?

    # Get organization_id from params or current context
    organization_id = params[:organization_id] || current_user.current_organization_id

    # Validate organization access
    if organization_id.present? && !current_user.in_organization?(organization_id)
      @user.errors.add(:base, "Invalid organization")
      render :new, status: :unprocessable_entity and return
    end

    if @user.save
      @user.add_role(:admin) if params[:user][:make_admin] == "1"
      @user.send_admin_invitation!

      # Create pending invitation for the specified organization
      if organization_id.present?
        org = Organization.find(organization_id)

        # Add user to organization with pending status
        membership = OrganizationMembership.find_or_create_by!(
          organization: org,
          user: @user
        ) do |m|
          m.status = :pending
          m.role = :member
        end

        # Create a pending invitation
        invitation = Invitation.create!(
          user: @user,
          organization: org,
          invitable: org,
          invitable_type: "Organization",
          email: @user.email,
          invited_by: current_user,
          status: "pending",
          permission: "read"
        )
        # Set as current organization for admin-invited users
        @user.update!(current_organization_id: org.id)
      elsif @user.organizations.any?
        # If no org specified but user has orgs, set the first one
        @user.update!(current_organization_id: @user.organizations.first.id)
      end

      respond_to do |format|
        format.html { redirect_to admin_user_path(@user), notice: "User created successfully." }
        format.turbo_stream { redirect_to admin_users_path(organization_id: organization_id), status: :see_other }
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

  def resend_invitation
    authorize @user, :toggle_status?

    # Find the pending invitation for this user (created for Organization)
    invitation = Invitation.find_by(user_id: @user.id, status: "pending", invitable_type: "Organization")

    if invitation
      # Resend the invitation
      invitation.update!(
        invitation_token: invitation.generate_token_for(:invitation),
        invitation_sent_at: Time.current
      )

      # Send the email
      AdminMailer.user_invitation(@user, invitation.invitation_token).deliver_later

      message = "Invitation resent to #{@user.email}"
    else
      message = "No pending invitation found for this user."
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
