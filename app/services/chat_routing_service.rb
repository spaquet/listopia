# app/services/chat_routing_service.rb
#
# Service for determining when chat should navigate to a page instead of
# rendering results in the chat interface.
#
# Analyzes user intent and LLM responses to decide if the request should
# trigger navigation to an existing app page (users list, team management, etc.)
# or be handled as a regular chat response.

class ChatRoutingService < ApplicationService
  def initialize(user_message:, chat:, user:, organization:)
    @user_message = user_message
    @chat = chat
    @user = user
    @organization = organization
  end

  def call
    # Check if message should trigger navigation
    routing_intent = detect_routing_intent(@user_message.content)

    if routing_intent.present?
      success(data: routing_intent)
    else
      success(data: { action: :chat, path: nil })
    end
  end

  private

  # Detect if user message implies they want to see a page, not chat results
  def detect_routing_intent(message)
    intent = detect_management_intent(message) ||
             detect_list_intent(message) ||
             detect_team_intent(message) ||
             detect_user_intent(message)

    intent
  end

  # Detect if user wants to manage users, orgs, or teams
  def detect_management_intent(message)
    message_lower = message.downcase

    # User management intents
    if message_match?(message_lower, %w[show active users list users members users page])
      { action: :navigate, path: :admin_users, description: "Show all users" }
    elsif message_match?(message_lower, %w[create add user new user])
      { action: :navigate, path: :new_admin_user, description: "Create new user" }
    # Organization management intents
    elsif message_match?(message_lower, %w[show organizations list organizations all orgs org page])
      { action: :navigate, path: :admin_organizations, description: "Show all organizations" }
    elsif message_match?(message_lower, %w[create add organization new org])
      { action: :navigate, path: :new_admin_organization, description: "Create new organization" }
    # Team management intents
    elsif message_match?(message_lower, %w[show teams list teams all teams])
      { action: :navigate, path: :organization_teams, description: "Show all teams" }
    elsif message_match?(message_lower, %w[create add team new team])
      { action: :navigate, path: :new_organization_team, description: "Create new team" }
    # Admin dashboard
    elsif message_match?(message_lower, %w[show dashboard admin dashboard overview])
      { action: :navigate, path: :admin_dashboard, description: "Show admin dashboard" }
    else
      nil
    end
  end

  # Detect list-related intents
  def detect_list_intent(message)
    message_lower = message.downcase

    if message_match?(message_lower, %w[show browse all lists my lists])
      { action: :navigate, path: :lists, description: "Show all lists" }
    elsif message_match?(message_lower, %w[create add list new list])
      { action: :navigate, path: :new_list, description: "Create new list" }
    else
      nil
    end
  end

  # Detect team-related intents
  def detect_team_intent(message)
    message_lower = message.downcase

    if message_match?(message_lower, %w[team members show members])
      if @chat.focused_resource.is_a?(Team)
        { action: :navigate, path: :team, resource: @chat.focused_resource, description: "Show team details" }
      else
        { action: :navigate, path: :organization_teams, description: "Show all teams" }
      end
    else
      nil
    end
  end

  # Detect user-related intents
  def detect_user_intent(message)
    message_lower = message.downcase

    if message_match?(message_lower, %w[show profile my profile user profile account])
      { action: :navigate, path: :profile, description: "Show user profile" }
    elsif message_match?(message_lower, %w[show settings account settings preferences])
      { action: :navigate, path: :settings_user, description: "Show account settings" }
    else
      nil
    end
  end

  # Helper to match message against keywords
  def message_match?(message_lower, keywords)
    keywords.any? { |keyword| message_lower.include?(keyword) }
  end

  # Build URL for routing intent
  def build_url(path, resource: nil)
    case path
    when :admin_users
      "/admin/users"
    when :new_admin_user
      "/admin/users/new"
    when :admin_organizations
      "/admin/organizations"
    when :new_admin_organization
      "/admin/organizations/new"
    when :admin_dashboard
      "/admin"
    when :organization_teams
      "/organizations/#{@organization.id}/teams"
    when :new_organization_team
      "/organizations/#{@organization.id}/teams/new"
    when :lists
      "/lists"
    when :new_list
      "/lists/new"
    when :team
      "/organizations/#{@organization.id}/teams/#{resource.id}" if resource
    when :profile
      "/profile"
    when :settings_user
      "/settings"
    else
      nil
    end
  end
end
