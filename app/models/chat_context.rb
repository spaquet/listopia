# app/models/chat_context.rb
#
# ChatContext provides context-aware information for the unified chat system.
# It adapts message rendering, suggestions, and behavior based on where the chat
# appears (dashboard, floating, inline) and what the user is currently viewing.

class ChatContext
  attr_reader :user, :organization, :chat, :location, :focused_resource

  # Context locations where chat can appear
  LOCATIONS = {
    dashboard: "dashboard",        # Main dashboard view
    floating: "floating",          # Floating chat button
    list_detail: "list_detail",    # Viewing a specific list
    team_view: "team_view"         # Viewing team details
  }.freeze

  def initialize(chat:, user:, organization:, location: :dashboard, focused_resource: nil)
    @chat = chat
    @user = user
    @organization = organization
    @location = location.to_sym
    @focused_resource = focused_resource

    validate_context!
  end

  # String representation for templates
  def to_s
    "ChatContext(#{location}, #{focused_resource_name})"
  end

  # Check if chat is in specific location
  def in_location?(*locations)
    locations.map(&:to_sym).include?(location)
  end

  # Get focused resource name for UI display
  def focused_resource_name
    return "Lists" unless focused_resource.present?

    case focused_resource
    when List
      "List: #{focused_resource.title}"
    when Team
      "Team: #{focused_resource.name}"
    when Organization
      "Organization: #{focused_resource.name}"
    else
      focused_resource.class.name
    end
  end

  # Get context-aware suggestions based on location and focused resource
  def suggestions
    base_suggestions = [
      { command: "/search", description: "Find your lists" },
      { command: "/browse", description: "Browse available lists" },
      { command: "/help", description: "See all commands" }
    ]

    return base_suggestions unless focused_resource.present?

    # Add resource-specific suggestions
    case focused_resource
    when List
      base_suggestions.concat([
        { command: "/items", description: "Show items in this list" },
        { command: "/info", description: "Get list details" },
        { command: "/share", description: "Share this list" }
      ])
    when Team
      base_suggestions.concat([
        { command: "/members", description: "Show team members" },
        { command: "/lists", description: "Show team lists" }
      ])
    end

    base_suggestions
  end

  # Get UI configuration based on location
  def ui_config
    case location
    when :dashboard
      {
        show_sidebar: true,
        sidebar_width: "lg:w-1/3",
        chat_height: "h-[600px]",
        position: "static",
        show_new_chat_button: true,
        show_history: true,
        responsive: "grid-cols-1 lg:grid-cols-3"
      }
    when :floating
      {
        show_sidebar: false,
        sidebar_width: nil,
        chat_height: "h-96",
        position: "fixed bottom-6 right-6 z-50",
        show_new_chat_button: false,
        show_history: false,
        responsive: "w-96 max-w-[90vw]"
      }
    when :list_detail
      {
        show_sidebar: false,
        sidebar_width: nil,
        chat_height: "h-[400px]",
        position: "static",
        show_new_chat_button: true,
        show_history: false,
        responsive: "w-full"
      }
    when :team_view
      {
        show_sidebar: false,
        sidebar_width: nil,
        chat_height: "h-[400px]",
        position: "static",
        show_new_chat_button: true,
        show_history: false,
        responsive: "w-full"
      }
    else
      {
        show_sidebar: true,
        sidebar_width: "lg:w-1/3",
        chat_height: "h-96",
        position: "static",
        show_new_chat_button: true,
        show_history: true,
        responsive: "w-full"
      }
    end
  end

  # Check if user has access to focused resource
  def can_access_focused_resource?
    return true unless focused_resource.present?

    case focused_resource
    when List
      user.lists.include?(focused_resource) ||
        focused_resource.list_collaborations.exists?(user: user)
    when Team
      user.teams.exists?(organization: organization) &&
        organization.teams.include?(focused_resource)
    when Organization
      user.in_organization?(organization)
    else
      false
    end
  end

  # Get RAG context if resource is List
  def rag_context
    return {} unless focused_resource.is_a?(List)

    {
      resource_type: "List",
      resource_id: focused_resource.id,
      resource_title: focused_resource.title,
      item_count: focused_resource.list_items.count,
      collaborator_count: focused_resource.collaborators.count
    }
  end

  # Build system prompt based on context
  def system_prompt
    base_prompt = "You are an AI assistant for Listopia, a collaborative list management application. " \
                  "You help users organize their tasks, collaborate with teams, and find information efficiently."

    return base_prompt unless focused_resource.present?

    case focused_resource
    when List
      base_prompt + " The user is currently viewing the list '#{focused_resource.title}'. " \
                    "You can help them manage items, share the list, or search related content."
    when Team
      base_prompt + " The user is viewing the team '#{focused_resource.name}'. " \
                    "You can help them find team members, list team resources, or manage team activities."
    else
      base_prompt
    end
  end

  private

  def validate_context!
    raise ArgumentError, "Invalid location: #{location}" unless LOCATIONS.values.include?(location.to_s)
    raise ArgumentError, "User must be present" unless user.present?
    raise ArgumentError, "Organization must be present" unless organization.present?
    raise ArgumentError, "Chat must be present" unless chat.present?
  end
end
