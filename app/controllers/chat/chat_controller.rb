# app/controllers/chat/chat_controller.rb

class Chat::ChatController < ApplicationController
  def create_message
    @mcp_service = McpService.new(
      user: current_user,
      context: build_chat_context,
      chat: current_user.current_chat
    )

    response_content = @mcp_service.process_message(params[:message])

    render turbo_stream: turbo_stream.append(
      "chat-messages",
      partial: "chat/assistant_message",
      locals: { message: response_content } # Fixed: message not content
    )
  end

  def load_history
    @chat = current_user.current_chat
    @messages = @chat.latest_messages_with_includes if @chat

    render turbo_stream: turbo_stream.replace(
      "chat-messages",
      partial: "chat/messages_history",
      locals: { messages: @messages || [] }
    )
  end

  private

  def build_chat_context
    {
      page: "#{controller_name}##{action_name}",
      current_page: params[:current_page],
      **params.fetch(:context, {}).permit!.to_h
    }
  end
end
