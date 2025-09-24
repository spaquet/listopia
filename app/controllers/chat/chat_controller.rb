# app/controllers/chat/chat_controller.rb
class Chat::ChatController < ApplicationController
  before_action :authenticate_user!

  def create_message
    message = chat_params[:message]
    context = chat_params[:context] || {}
    current_page = chat_params[:current_page]

    # Get or create user's current chat
    chat = current_user.current_chat

    # Process message through MCP with database persistence
    begin
      mcp_service = McpService.new(user: current_user, context: context, chat: chat)
      response_message = mcp_service.process_message(message)
    rescue McpService::AuthorizationError => e
      response_message = "I'm sorry, but #{e.message.downcase}. Please check your permissions and try again."

      # Still save the error response to chat
      chat.add_assistant_message(response_message, metadata: { error_type: "authorization" })
    rescue => e
      Rails.logger.error "MCP Error: #{e.message}"
      response_message = "I encountered an error processing your request. Please try again or contact support if the issue persists."

      # Save error to chat
      chat.add_assistant_message(response_message, metadata: { error_type: "system", error: e.message })
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append(
          "chat-messages",
          partial: "chat/assistant_message",
          locals: { message: response_message }
        ), content_type: "text/vnd.turbo-stream.html"
      end
      format.html { redirect_back(fallback_location: root_path) }
      format.json { render json: { message: response_message } }
    end
  end

  # Load chat history for a user
  def load_history
    begin
      chat = current_user.current_chat

      # Handle case where user has no chat yet
      unless chat
        render turbo_stream: turbo_stream.replace(
          "chat-messages",
          partial: "chat/empty_history"
        ), content_type: "text/vnd.turbo-stream.html"
        return
      end

      # Use the corrected method name
      messages = chat.latest_messages_with_includes(50)

      render turbo_stream: turbo_stream.replace(
        "chat-messages",
        partial: "chat/messages_history",
        locals: { messages: messages }
      ), content_type: "text/vnd.turbo-stream.html"

    rescue => e
      Rails.logger.error "Chat history loading error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Render empty history on error
      render turbo_stream: turbo_stream.replace(
        "chat-messages",
        partial: "chat/empty_history"
      ), content_type: "text/vnd.turbo-stream.html"
    end
  end

  private

  def chat_params
    # Allow all the parameters that the frontend sends, including nested chat parameter
    params.permit(:message, :current_page, context: {}, chat: { context: {} })
  end
end
