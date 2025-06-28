# app/controllers/chat_controller.rb
class ChatController < ApplicationController
  before_action :authenticate_user!

  def create_message
    message = chat_params[:message]
    context = chat_params[:context] || {}
    current_page = chat_params[:current_page]

    # Process message through MCP
    begin
      mcp_service = McpService.new(user: current_user, context: context)
      response_message = mcp_service.process_message(message)
    rescue McpService::AuthorizationError => e
      response_message = "I'm sorry, but #{e.message.downcase}. Please check your permissions and try again."
    rescue => e
      Rails.logger.error "MCP Error: #{e.message}"
      response_message = "I encountered an error processing your request. Please try again or contact support if the issue persists."
    end

    respond_with_turbo_stream do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.append(
            "chat-messages",
            partial: "chat/assistant_message",
            locals: { message: response_message }
          ),
          # Refresh lists if they might have been modified
          refresh_lists_if_needed(context)
        ].compact
      end
    end
  end

  private

  def chat_params
    params.permit(:message, :current_page, context: {})
  end

  def refresh_lists_if_needed(context)
    # If user is on a list page, refresh the list content
    if context["page"]&.starts_with?("lists#") && context["list_id"]
      turbo_stream.replace(
        "list-content",
        partial: "lists/list_content",
        locals: { list: current_user.accessible_lists.find_by(id: context["list_id"]) }
      )
    end
  rescue
    # Silently fail if list refresh isn't possible
    nil
  end
end
