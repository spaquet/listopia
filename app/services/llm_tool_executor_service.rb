# app/services/llm_tool_executor_service.rb
#
# Executes tool calls from the LLM.
# When the LLM decides to call a tool (e.g., list_users, create_team),
# this service executes the corresponding database query or operation
# and returns the result in a format the LLM can understand.

class LlmToolExecutorService < ApplicationService
  def initialize(tool_name:, tool_input:, user:, organization:, chat_context:)
    @tool_name = tool_name
    @tool_input = tool_input || {}
    @user = user
    @organization = organization
    @chat_context = chat_context
  end

  def call
    case @tool_name
    when "navigate_to_page"
      execute_navigate(@tool_input)
    when "list_users"
      execute_list_users(@tool_input)
    when "list_teams"
      execute_list_teams(@tool_input)
    when "list_organizations"
      execute_list_organizations(@tool_input)
    when "list_lists"
      execute_list_lists(@tool_input)
    when "search"
      execute_search(@tool_input)
    when "create_user"
      execute_create_user(@tool_input)
    when "create_team"
      execute_create_team(@tool_input)
    when "create_list"
      execute_create_list(@tool_input)
    when "update_user"
      execute_update_user(@tool_input)
    when "update_team"
      execute_update_team(@tool_input)
    when "suspend_user"
      execute_suspend_user(@tool_input)
    else
      failure(errors: [ "Unknown tool: #{@tool_name}" ])
    end
  rescue Pundit::NotAuthorizedError
    failure(errors: [ "You don't have permission to perform this action" ])
  rescue ActiveRecord::RecordNotFound => e
    failure(errors: [ "Resource not found: #{e.message}" ])
  rescue StandardError => e
    Rails.logger.error("Tool executor error: #{@tool_name} - #{e.message}")
    failure(errors: [ e.message ])
  end

  private

  # Navigate to a page - returns routing information
  def execute_navigate(input)
    page = input["page"].to_s.downcase
    filter = input["filter"] || {}

    path = case page
    when "admin_users"
             "/admin/users"
    when "admin_organizations"
             "/admin/organizations"
    when "admin_teams"
             "/admin/teams"
    when "organization_teams"
             "/organizations/#{@organization.id}/teams"
    when "admin_dashboard"
             "/admin"
    when "lists"
             "/lists"
    when "profile"
             "/profile"
    when "settings"
             "/settings"
    else
             nil
    end

    if path.nil?
      failure(errors: [ "Invalid page: #{page}" ])
    else
      success(data: {
        type: "navigation",
        path: path,
        filters: filter.compact,
        message: "Navigating to #{page.humanize}..."
      })
    end
  end

  # List users in organization
  def execute_list_users(input)
    authorize_read_users!

    query = input["query"].to_s
    status = input["status"].to_s if input["status"].present?
    role = input["role"].to_s if input["role"].present?
    page = (input["page"] || 1).to_i
    per_page = [ (input["per_page"] || 20).to_i, 100 ].min

    users = @organization.users
    users = users.where("name ILIKE ? OR email ILIKE ?", "%#{query}%", "%#{query}%") if query.present?
    users = users.joins(:organization_memberships)
                 .where(organization_memberships: { status: status }) if status.present?
    users = users.joins(:organization_memberships)
                 .where(organization_memberships: { role: role }) if role.present?

    total = users.count
    users = users.distinct.page(page).per(per_page)

    success(data: {
      type: "list",
      resource_type: "User",
      total_count: total,
      page: page,
      per_page: per_page,
      items: users.map { |u| format_user(u) }
    })
  end

  # List teams in organization
  def execute_list_teams(input)
    query = input["query"].to_s
    page = (input["page"] || 1).to_i
    per_page = [ (input["per_page"] || 20).to_i, 100 ].min

    teams = @organization.teams
    teams = teams.where("name ILIKE ? OR slug ILIKE ?", "%#{query}%", "%#{query}%") if query.present?

    total = teams.count
    teams = teams.page(page).per(per_page)

    success(data: {
      type: "list",
      resource_type: "Team",
      total_count: total,
      page: page,
      per_page: per_page,
      items: teams.map { |t| format_team(t) }
    })
  end

  # List organizations accessible by user
  def execute_list_organizations(input)
    query = input["query"].to_s
    status = input["status"].to_s if input["status"].present?
    page = (input["page"] || 1).to_i

    orgs = @user.organizations
    orgs = orgs.where("name ILIKE ? OR slug ILIKE ?", "%#{query}%", "%#{query}%") if query.present?
    orgs = orgs.where(status: status) if status.present?

    total = orgs.count
    orgs = orgs.page(page).per(20)

    success(data: {
      type: "list",
      resource_type: "Organization",
      total_count: total,
      page: page,
      items: orgs.map { |o| format_organization(o) }
    })
  end

  # List lists in organization
  def execute_list_lists(input)
    query = input["query"].to_s
    status = input["status"].to_s if input["status"].present?
    owner_name = input["owner"].to_s if input["owner"].present?
    page = (input["page"] || 1).to_i

    lists = @organization.lists
    lists = lists.where("title ILIKE ? OR description ILIKE ?", "%#{query}%", "%#{query}%") if query.present?
    lists = lists.where(status: status) if status.present?
    lists = lists.joins(:owner).where("users.name ILIKE ?", "%#{owner_name}%") if owner_name.present?

    total = lists.count
    lists = lists.page(page).per(20)

    success(data: {
      type: "list",
      resource_type: "List",
      total_count: total,
      page: page,
      items: lists.map { |l| format_list(l) }
    })
  end

  # Search across resources
  def execute_search(input)
    query = input["query"].to_s
    resource_type = (input["resource_type"] || "all").to_s.downcase
    limit = [ (input["limit"] || 10).to_i, 50 ].min

    result = SearchService.new(query: query, user: @user).call

    if result.failure?
      return success(data: {
        type: "search_results",
        query: query,
        total_count: 0,
        items: []
      })
    end

    items = (result.data || []).take(limit).map { |r| format_search_result(r) }

    success(data: {
      type: "search_results",
      query: query,
      resource_type: resource_type,
      total_count: items.length,
      items: items
    })
  end

  # Create new user
  def execute_create_user(input)
    authorize_write_users!

    email = input["email"].to_s.strip
    name = input["name"].to_s.strip
    # Default to "member" role - user must explicitly request admin/lead role
    role = (input["role"] || "member").to_s.downcase

    return failure(errors: [ "Email is required" ]) if email.blank?
    return failure(errors: [ "Name is required" ]) if name.blank?
    return failure(errors: [ "Role must be 'member' or 'admin'" ]) unless %w[member admin].include?(role)

    # Check if user already exists
    existing_user = User.find_by(email: email)
    if existing_user
      # If user exists, just add them to organization if not already a member
      membership = existing_user.organization_memberships.find_by(organization: @organization)
      if membership
        return success(data: {
          type: "resource",
          resource_type: "User",
          action: "added",
          item: format_user(existing_user)
        })
      end

      # Add existing user to organization
      OrganizationMembership.create!(
        user: existing_user,
        organization: @organization,
        role: role,
        status: :active
      )

      return success(data: {
        type: "resource",
        resource_type: "User",
        action: "added",
        item: format_user(existing_user)
      })
    end

    # Create new user with temporary password
    user = User.create!(
      email: email,
      name: name,
      password: SecureRandom.alphanumeric(16)
    )

    # Add to organization with specified role
    OrganizationMembership.create!(
      user: user,
      organization: @organization,
      role: role,
      status: :pending
    )

    # Send invitation email to set up account
    OrganizationInvitationMailer.invite_email(user, @organization).deliver_later

    success(data: {
      type: "resource",
      resource_type: "User",
      action: "created",
      item: format_user(user)
    })
  end

  # Create new team
  def execute_create_team(input)
    authorize_write_teams!

    name = input["name"].to_s.strip
    description = input["description"].to_s.strip if input["description"].present?

    return failure(errors: [ "Team name is required" ]) if name.blank?

    team = Team.create!(
      organization: @organization,
      name: name,
      description: description,
      created_by: @user
    )

    success(data: {
      type: "resource",
      resource_type: "Team",
      action: "created",
      item: format_team(team)
    })
  end

  # Create new list
  def execute_create_list(input)
    title = input["title"].to_s.strip
    description = input["description"].to_s.strip if input["description"].present?
    team_id = input["team_id"].to_s if input["team_id"].present?

    return failure(errors: [ "List title is required" ]) if title.blank?

    list_params = {
      organization: @organization,
      owner: @user,
      title: title,
      description: description
    }

    list_params[:team] = Team.find(team_id) if team_id.present?

    list = List.create!(list_params)

    success(data: {
      type: "resource",
      resource_type: "List",
      action: "created",
      item: format_list(list)
    })
  end

  # Update user
  def execute_update_user(input)
    authorize_write_users!

    user_id = input["user_id"].to_s
    user = User.find(user_id)

    user.name = input["name"].to_s if input["name"].present?
    user.email = input["email"].to_s if input["email"].present?

    if input["status"].present?
      membership = user.organization_memberships.find_by(organization: @organization)
      membership.update!(status: input["status"]) if membership
    end

    if input["role"].present?
      membership = user.organization_memberships.find_by(organization: @organization)
      membership.update!(role: input["role"]) if membership
    end

    user.save!

    success(data: {
      type: "resource",
      resource_type: "User",
      action: "updated",
      item: format_user(user)
    })
  end

  # Update team
  def execute_update_team(input)
    authorize_write_teams!

    team_id = input["team_id"].to_s
    team = Team.find(team_id)

    team.name = input["name"].to_s if input["name"].present?
    team.description = input["description"].to_s if input["description"].present?

    team.save!

    success(data: {
      type: "resource",
      resource_type: "Team",
      action: "updated",
      item: format_team(team)
    })
  end

  # Suspend/unsuspend user
  def execute_suspend_user(input)
    authorize_write_users!

    user_id = input["user_id"].to_s
    action = (input["action"] || "suspend").to_s.downcase

    user = User.find(user_id)
    membership = user.organization_memberships.find_by(organization: @organization)

    return failure(errors: [ "User is not in this organization" ]) unless membership

    new_status = action == "suspend" ? :suspended : :active
    membership.update!(status: new_status)

    success(data: {
      type: "resource",
      resource_type: "User",
      action: action,
      item: format_user(user)
    })
  end

  # Format helpers
  def format_user(user)
    membership = user.organization_memberships.find_by(organization: @organization)
    {
      id: user.id,
      name: user.name,
      email: user.email,
      role: membership&.role,
      status: membership&.status,
      created_at: user.created_at.strftime("%b %d, %Y")
    }
  end

  def format_team(team)
    {
      id: team.id,
      name: team.name,
      slug: team.slug,
      description: team.description,
      members_count: team.team_memberships.count,
      created_at: team.created_at.strftime("%b %d, %Y")
    }
  end

  def format_organization(org)
    {
      id: org.id,
      name: org.name,
      slug: org.slug,
      size: org.size,
      status: org.status,
      members_count: org.users.count,
      teams_count: org.teams.count
    }
  end

  def format_list(list)
    {
      id: list.id,
      title: list.title,
      description: list.description,
      status: list.status,
      owner: list.owner&.name,
      items_count: list.list_items.count,
      url: "/lists/#{list.id}"
    }
  end

  def format_search_result(record)
    case record
    when User
      {
        type: "User",
        id: record.id,
        title: record.name,
        subtitle: record.email
      }
    when List
      {
        type: "List",
        id: record.id,
        title: record.title,
        subtitle: "Owner: #{record.owner&.name}"
      }
    when ListItem
      {
        type: "ListItem",
        id: record.id,
        title: record.title,
        subtitle: "in #{record.list.title}"
      }
    else
      {
        type: record.class.name,
        id: record.id,
        title: record.to_s
      }
    end
  end

  # Authorization helpers
  def authorize_read_users!
    authorize(:admin_user, :read?)
  end

  def authorize_write_users!
    authorize(:admin_user, :write?)
  end

  def authorize_write_teams!
    authorize(:team, :create?)
  end
end
