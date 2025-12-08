# app/services/chat_mention_parser.rb
#
# Parses and processes @mentions and #references in chat messages.
# - @username mentions users (collaborators, team members)
# - #listname references lists, items, and other resources
#
# Returns formatted mentions/references with links and metadata.

class ChatMentionParser
  attr_reader :message, :user, :organization

  def initialize(message:, user:, organization:)
    @message = message.to_s
    @user = user
    @organization = organization
  end

  # Parse message and extract all mentions and references
  # Returns: { text: processed_text, mentions: [], references: [] }
  def call
    mentions = extract_mentions
    references = extract_references

    {
      text: message,
      mentions: mentions,
      references: references,
      has_mentions: mentions.any?,
      has_references: references.any?
    }
  end

  private

  # Extract @mentions from message
  # Matches: @username, @first.last, @email
  def extract_mentions
    mention_pattern = /@([\w.\-]+)/
    matches = message.scan(mention_pattern)

    mentions = matches.map do |match|
      mention_text = match[0]
      find_user_by_mention(mention_text)
    end

    mentions.compact
  end

  # Extract #references from message
  # Matches: #listname, #list-name, #item-123
  def extract_references
    reference_pattern = /#([\w\-]+)/
    matches = message.scan(reference_pattern)

    references = matches.map do |match|
      reference_text = match[0]
      find_resource_by_reference(reference_text)
    end

    references.compact
  end

  # Find user by mention (username, email, or name)
  def find_user_by_mention(mention_text)
    # Try to find user by:
    # 1. Email (before @)
    # 2. Name (first and last)
    # 3. Username (if we had one)

    user = User.find_by(email: "#{mention_text}@example.com") ||
            User.where(organization_id: organization.id)
              .joins(:organization_memberships)
              .where(organization_memberships: { organization_id: organization.id })
              .where("LOWER(users.name) ILIKE ?", "%#{mention_text}%")
              .first

    return nil unless user

    # Verify user is in same organization
    return nil unless user.in_organization?(organization)

    {
      type: "user",
      id: user.id,
      name: user.name,
      email: user.email,
      mention_text: "@#{mention_text}"
    }
  end

  # Find resource by reference (#listname, #item-123, etc)
  def find_resource_by_reference(reference_text)
    # Try to find:
    # 1. List by title (case-insensitive)
    # 2. List item by title
    # 3. Team by name

    # Check for list by title or public_slug
    list = List.where(organization_id: organization.id)
               .where("LOWER(title) ILIKE ? OR LOWER(public_slug) = ?", "%#{reference_text}%", reference_text.downcase)
               .first

    if list
      return {
        type: "list",
        id: list.id,
        title: list.title,
        description: list.description,
        reference_text: "##{reference_text}",
        url: Rails.application.routes.url_helpers.list_path(list)
      }
    end

    # Check for list item by title
    list_item = ListItem.joins(:list)
                        .where(lists: { organization_id: organization.id })
                        .where("LOWER(list_items.title) ILIKE ?", "%#{reference_text}%")
                        .first

    if list_item
      return {
        type: "item",
        id: list_item.id,
        title: list_item.title,
        list_id: list_item.list_id,
        list_title: list_item.list.title,
        reference_text: "##{reference_text}",
        url: Rails.application.routes.url_helpers.list_item_path(list_item.list, list_item)
      }
    end

    # Check for team by name
    team = Team.where(organization_id: organization.id)
               .where("LOWER(name) ILIKE ? OR LOWER(slug) = ?", "%#{reference_text}%", reference_text.downcase)
               .first

    if team
      return {
        type: "team",
        id: team.id,
        name: team.name,
        reference_text: "##{reference_text}",
        url: Rails.application.routes.url_helpers.organization_team_path(organization, team)
      }
    end

    nil
  end
end
