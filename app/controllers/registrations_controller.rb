# app/controllers/registrations_controller.rb
class RegistrationsController < ApplicationController
  before_action :redirect_if_authenticated, except: [ :setup_password, :complete_setup_password ]

  # Show registration form
  def new
    @user = User.new
  end

  # Handle user registration
  def create
    @user = User.new(registration_params)

    if @user.save
      # Create personal organization for new user
      create_personal_organization(@user)

      # Generate email verification token and send email
      token = @user.generate_email_verification_token
      AuthMailer.email_verification(@user, token).deliver_now

      # Check for pending collaboration invitation
      if session[:pending_collaboration_token]
        collaboration = ListCollaboration.find_by_invitation_token(session[:pending_collaboration_token])
        if collaboration && collaboration.email == @user.email
          collaboration.update!(user: @user, email: nil)
          session.delete(:pending_collaboration_token)
          flash[:notice] = "Account created and collaboration invitation accepted! Please verify your email to get started."
        end
      end

      # Store org invitation token if present
      if session[:pending_organization_invitation_token]
        session[:org_invitation_token] = session[:pending_organization_invitation_token]
        session.delete(:pending_organization_invitation_token)
        session.delete(:pending_organization_invitation_email)
      end

      redirect_to verify_email_path, notice: "Please check your email to verify your account."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # Handle email verification
  def verify_email
    token = params[:token]
    user = User.find_by_email_verification_token(token)

    if user
      user.verify_email!
      sign_in(user)

      # If they just accepted a collaboration, redirect to the list
      if session[:pending_collaboration_token]
        collaboration = ListCollaboration.find_by_invitation_token(session[:pending_collaboration_token])
        if collaboration && collaboration.user == user
          session.delete(:pending_collaboration_token)
          redirect_to collaboration.list, notice: "Email verified! Welcome to the collaboration!"
          return
        end
      end

      # If they have a pending organization invitation, redirect to accept it
      if session[:org_invitation_token]
        org_token = session[:org_invitation_token]
        session.delete(:org_invitation_token)
        redirect_to accept_organization_invitation_path(org_token), notice: "Email verified! Now accepting your organization invitation..."
        return
      end

      redirect_to dashboard_path, notice: "Email verified! Welcome to Listopia!"
    else
      redirect_to root_path, alert: "Invalid or expired verification link."
    end
  end

  # Show email verification pending page
  def email_verification_pending
    # Just render the template
  end

  # Handle admin invitation setup - user sets their password
  def setup_password
    token = params[:token]
    @user = User.find_by_email_verification_token(token)

    if @user.nil?
      redirect_to new_session_path, alert: "Invalid or expired invitation link."
      return
    end

    if @user.email_verified?
      redirect_to new_session_path, alert: "You have already set up your password."
      return
    end

    # Render setup_password view with @user instance variable
    render :setup_password, locals: { token: token }
  end

  # Handle password setup submission
  def complete_setup_password
    token = params[:token]
    @user = User.find_by_email_verification_token(token)

    if @user.nil?
      redirect_to new_session_path, alert: "Invalid or expired invitation link."
      return
    end

    if @user.email_verified?
      redirect_to new_session_path, alert: "You have already set up your password."
      return
    end

    # Update password
    if @user.update(password_params_setup)
      # Now verify the email and sign them in
      @user.verify_email!

      # Set user status to active (from pending_verification)
      @user.update!(status: :active)

      # Check if user has a pending organization invitation
      pending_invitation = Invitation.find_by(
        user_id: @user.id,
        status: "pending",
        invitable_type: "Organization"
      )

      # Ensure the user has a current_organization set before signing in
      # (sign_in will use this to set the session)
      if @user.current_organization_id.nil? && @user.organizations.any?
        @user.update!(current_organization_id: @user.organizations.first.id)
      end

      sign_in(@user)

      # If user has a pending organization invitation, auto-accept it
      if pending_invitation
        pending_invitation.update!(
          status: "accepted",
          invitation_accepted_at: Time.current
        )
        # Also update the organization membership to active
        membership = pending_invitation.organization.organization_memberships.find_by(user: @user)
        membership.update!(status: :active) if membership && membership.status_pending?

        redirect_to dashboard_path, notice: "Password set successfully! You've been added to #{pending_invitation.organization.name}."
      else
        redirect_to dashboard_path, notice: "Password set successfully! Welcome to Listopia!"
      end
    else
      flash.now[:alert] = @user.errors[:password].first || "Password update failed"
      render :setup_password, status: :unprocessable_entity, locals: { token: token }
    end
  end

  private

  # Strong parameters for user registration
  def registration_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation)
  end

  # Strong parameters for password setup (admin-invited users)
  def password_params_setup
    params.require(:user).permit(:password, :password_confirmation)
  end

  # Redirect authenticated users away from registration
  def redirect_if_authenticated
    redirect_to dashboard_path if current_user
  end

  # Create a personal organization for new user
  def create_personal_organization(user)
    org_name = "#{user.name}'s Workspace"
    slug_base = user.email.split("@")[0]
    slug = "#{slug_base}-#{user.id[0...8]}"

    org = Organization.create!(
      name: org_name,
      slug: slug,
      size: :small,
      status: :active,
      created_by_id: user.id
    )

    OrganizationMembership.create!(
      organization: org,
      user: user,
      role: :owner,
      status: :active,
      joined_at: Time.current
    )

    user.update!(current_organization_id: org.id)
  end
end
