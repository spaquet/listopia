# app/services/user_creation_service.rb
# Shared service for user creation across all interfaces (Admin UI, Chat, API, etc.)
# Handles all aspects of user creation: validation, model creation, org membership, invitations

class UserCreationService < ApplicationService
  def initialize(user_params:, created_by_user:, organization: nil, make_admin: false)
    @user_params = user_params
    @created_by_user = created_by_user
    @organization = organization
    @make_admin = make_admin
  end

  def call
    # Validate parameters
    validation_error = validate_parameters
    return failure(errors: [ validation_error ]) if validation_error

    # Create and save the user
    user = create_user_record
    return failure(errors: user.errors.full_messages) unless user.persisted?

    # Add admin role if requested
    user.add_role(:admin) if @make_admin

    # Set up organization membership and invitation
    setup_organization(user, @organization)

    # Send invitation email
    user.send_admin_invitation!

    success(data: {
      user: user,
      message: "User #{user.name} (#{user.email}) created successfully. Invitation sent."
    })
  rescue StandardError => e
    Rails.logger.error("User creation failed: #{e.class} - #{e.message}")
    failure(errors: [ "An unexpected error occurred while creating the user" ])
  end

  private

  # Validate that all required parameters are present
  def validate_parameters
    return "Email is required" if @user_params[:email].blank?
    return "Name is required" if @user_params[:name].blank?

    # Check if user already exists
    existing_user = User.find_by(email: @user_params[:email])
    return "User with email #{@user_params[:email]} already exists" if existing_user

    nil
  end

  # Create and save the user record
  def create_user_record
    user = User.new(@user_params)

    # Set required fields for admin-invited users
    user.generate_temp_password
    user.status = "pending_verification"

    user.save
    user
  end

  # Set up organization membership and invitation
  def setup_organization(user, organization)
    if organization.present?
      # Create organization membership
      OrganizationMembership.find_or_create_by!(
        organization: organization,
        user: user
      ) do |m|
        m.status = :pending
        m.role = :member
      end

      # Create invitation record
      Invitation.create!(
        user: user,
        organization: organization,
        invitable: organization,
        invitable_type: "Organization",
        email: user.email,
        invited_by: @created_by_user,
        status: "pending",
        permission: "read"
      )

      # Set as current organization
      user.update!(current_organization_id: organization.id)
    elsif user.organizations.any?
      # If no org specified but user has orgs, set the first one
      user.update!(current_organization_id: user.organizations.first.id)
    end
  end
end
