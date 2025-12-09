# app/controllers/chat_mentions_controller.rb
# Handles @ user mentions and # reference searches in chat
# Reuses UserFilterService and list search logic

class ChatMentionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_chat
  before_action :authorize_chat_access

  # GET /chats/:chat_id/mentions/search
  # Search for users in the current organization
  # Params: q (search query)
  def search_users
    query = params[:q].to_s.strip
    return render json: [] if query.blank?

    # Use UserFilterService to search users in current organization
    filter_service = UserFilterService.new(
      query: query,
      organization_id: @chat.organization_id
    )

    users = filter_service.filtered_users.limit(10).map do |user|
      {
        id: user.id,
        name: user.name,
        email: user.email,
        type: "user",
        avatar_url: user.avatar_url,
        mention_text: "@#{user.name.downcase.gsub(/\s+/, '.')}"
      }
    end

    render json: users
  end

  # GET /chats/:chat_id/mentions/search_references
  # Search for lists and items in the current organization
  # Params: q (search query)
  def search_references
    query = params[:q].to_s.strip
    return render json: [] if query.blank?

    references = []

    # Search for lists
    lists = List.where(organization_id: @chat.organization_id)
                .where("LOWER(title) ILIKE ?", "%#{query.downcase}%")
                .limit(5)
                .map do |list|
      {
        id: list.id,
        title: list.title,
        type: "list",
        description: list.description&.truncate(100),
        reference_text: "##{list.title.downcase.gsub(/\s+/, '-')}"
      }
    end

    references.concat(lists)

    # Search for list items
    list_items = ListItem.joins(:list)
                         .where(lists: { organization_id: @chat.organization_id })
                         .where("LOWER(list_items.title) ILIKE ?", "%#{query.downcase}%")
                         .limit(5)
                         .map do |item|
      {
        id: item.id,
        title: item.title,
        type: "item",
        list_title: item.list.title,
        reference_text: "##{item.title.downcase.gsub(/\s+/, '-')}"
      }
    end

    references.concat(list_items)

    render json: references
  end

  private

  def set_chat
    @chat = Chat.find(params[:id])
  end

  def authorize_chat_access
    unless @chat.user_id == current_user.id
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end
end
