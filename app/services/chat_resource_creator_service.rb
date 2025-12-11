# app/services/chat_resource_creator_service.rb
# Service to create resources (users, organizations, etc.) from chat parameter extraction
# Mirrors the logic from admin controllers but adapted for chat context

class ChatResourceCreatorService < ApplicationService
  def initialize(resource_type:, parameters:, created_by_user:, created_in_organization:)
    @resource_type = resource_type.downcase
    @parameters = parameters
    @created_by_user = created_by_user
    @created_in_organization = created_in_organization
  end

  def call
    case @resource_type
    when "user"
      create_user
    when "organization"
      create_organization
    when "team"
      create_team
    when "list"
      create_list
    else
      failure(errors: [ "Unknown resource type: #{@resource_type}" ])
    end
  end

  private

  def create_user
    # Combine first_name and last_name into name field
    full_name = build_full_name(@parameters)
    email = @parameters["email"] || @parameters[:email]
    bio = @parameters["bio"] || @parameters[:bio]
    avatar_url = @parameters["avatar_url"] || @parameters[:avatar_url]
    locale = @parameters["locale"] || @parameters[:locale] || "en"
    timezone = @parameters["timezone"] || @parameters[:timezone] || "UTC"

    return failure(errors: [ "Email is required to create a user" ]) unless email.present?
    return failure(errors: [ "Name is required to create a user" ]) unless full_name.present?

    # Prepare user params for the service
    user_params = {
      name: full_name,
      email: email,
      bio: bio,
      avatar_url: avatar_url,
      locale: locale,
      timezone: timezone,
      admin_notes: "Created via chat by #{@created_by_user.email}"
    }

    # Use UserCreationService to handle all user creation logic
    result = UserCreationService.new(
      user_params: user_params,
      created_by_user: @created_by_user,
      organization: @created_in_organization,
      make_admin: false
    ).call

    if result.success?
      user = result.data[:user]
      success(data: {
        type: "user",
        message: "User #{full_name} (#{email}) created successfully. Invitation sent.",
        resource: user,
        resource_id: user.id
      })
    else
      failure(errors: result.errors)
    end
  end

  def create_organization
    name = @parameters["name"] || @parameters[:name]
    description = @parameters["description"] || @parameters[:description]
    size = @parameters["size"] || @parameters[:size] || "small"

    return failure(errors: [ "Organization name is required" ]) unless name.present?

    # Check if organization with same name exists for this user
    existing_org = @created_by_user.organizations.find_by(name: name)
    return failure(errors: [ "You already have an organization named #{name}" ]) if existing_org

    organization = Organization.new(
      name: name,
      description: description,
      size: size,
      created_by: @created_by_user
    )

    unless organization.save
      return failure(errors: organization.errors.full_messages)
    end

    # Add creator as admin member
    OrganizationMembership.create!(
      organization: organization,
      user: @created_by_user,
      role: :admin,
      status: :active
    )

    success(data: {
      type: "organization",
      message: "Organization #{name} created successfully.",
      resource: organization,
      resource_id: organization.id
    })
  end

  def create_team
    name = @parameters["name"] || @parameters[:name]
    description = @parameters["description"] || @parameters[:description]

    return failure(errors: [ "Team name is required" ]) unless name.present?
    return failure(errors: [ "Organization is required to create a team" ]) unless @created_in_organization

    org = @created_in_organization

    # Check if team with same name exists in this organization
    existing_team = org.teams.find_by(name: name)
    return failure(errors: [ "Team #{name} already exists in #{org.name}" ]) if existing_team

    team = Team.new(
      organization: org,
      name: name,
      description: description,
      created_by: @created_by_user
    )

    unless team.save
      return failure(errors: team.errors.full_messages)
    end

    # Add creator as admin member
    team_membership = TeamMembership.create!(
      team: team,
      user: @created_by_user,
      organization_membership: @created_by_user.organization_memberships.find_by(organization: org),
      role: :admin
    )

    success(data: {
      type: "team",
      message: "Team #{name} created successfully in #{org.name}.",
      resource: team,
      resource_id: team.id
    })
  end

  def create_list
    # Extract parameters - support both symbol and string keys
    title = @parameters["title"] || @parameters[:title]
    description = @parameters["description"] || @parameters[:description]
    status = @parameters["status"] || @parameters[:status] || "draft"
    category = @parameters["category"] || @parameters[:category] || "personal"
    team_id = @parameters["team_id"] || @parameters[:team_id]
    items = @parameters["items"] || @parameters[:items]
    nested_lists = @parameters["nested_lists"] || @parameters[:nested_lists]

    return failure(errors: ["List title is required"]) unless title.present?
    return failure(errors: ["Organization is required to create a list"]) unless @created_in_organization

    # USE ListCreationService for all list creation logic
    # Benefits of delegating to the service:
    # - Consistent validation and error handling across chat and UI
    # - Proper Turbo Stream broadcasting to keep UI dashboards in sync with new lists
    # - Centralized position management for items (prevents unique constraint violations)
    # - Support for nested list hierarchies
    # - Atomic transactions ensure data integrity
    # - Maintainability: list creation logic in one place (not duplicated across services)
    # - Easier to add features (audit logging, webhooks, etc.) in one location
    #
    # This refactoring moved list/item creation out of ChatResourceCreatorService,
    # which now focuses on chat-specific orchestration and messaging.

    service = ListCreationService.new(@created_by_user)

    result = service.create_list_with_structure(
      title: title,
      description: description,
      status: status,
      list_type: category,
      team_id: team_id,
      organization: @created_in_organization,
      items: items || [],
      nested_lists: nested_lists || []
    )

    if result.success?
      list = result.data
      items_count = list.list_items.count
      sublists_count = list.sub_lists.count

      # Build success message
      message = "List \"#{title}\" created successfully."
      message += " (#{sublists_count} sub-lists created)" if sublists_count > 0
      message += " (#{items_count} items added)" if items_count > 0

      success(data: {
        type: "list",
        message: message,
        resource: list,
        resource_id: list.id,
        items_created: items_count,
        sublists_created: sublists_count
      })
    else
      failure(errors: result.errors)
    end
  end

  # Combine first_name and last_name into a single name
  def build_full_name(params)
    first_name = (params["first_name"] || params[:first_name]).to_s.strip
    last_name = (params["last_name"] || params[:last_name]).to_s.strip

    [ first_name, last_name ].filter(&:present?).join(" ")
  end
end
