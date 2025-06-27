# app/controllers/chat_controller.rb
class ChatController < ApplicationController
  before_action :authenticate_user!

  def create_message
    message = chat_params[:message]

    # For now, we'll just echo back with a placeholder response
    # Later this will integrate with MCP
    response_message = generate_placeholder_response(message)

    respond_with_turbo_stream do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append(
          "chat-messages",
          partial: "chat/assistant_message",
          locals: { message: response_message }
        )
      end
    end
  end

  private

  def chat_params
    params.require(:chat).permit(:message) if params[:chat]
    params.permit(:message) # Allow direct message param for now
  end

  def generate_placeholder_response(user_message)
    # Placeholder logic - will be replaced with MCP integration
    case user_message.downcase
    when /create.*list/
      "I'd love to help you create a list! Once I'm connected to the MCP system, I'll be able to create lists with items automatically. For now, you can use the 'New List' button in the navigation."
    when /add.*item/
      "Great idea! I'll be able to add items to your lists once the MCP integration is complete. Currently, you can add items by opening any of your existing lists."
    when /help|what can you do/
      "I'm your Listopia assistant! Soon I'll be able to help you:\n\n• Create new lists with items\n• Add items to existing lists\n• Update task priorities\n• Share lists with collaborators\n• Set reminders and due dates\n\nI'm currently in preview mode, but full functionality is coming soon!"
    when /hello|hi|hey/
      "Hello! I'm excited to help you manage your lists and tasks. What would you like to work on today?"
    else
      "I understand you want to work with '#{user_message}'. I'm still learning, but once my MCP integration is complete, I'll be able to help you create and manage lists much more naturally!"
    end
  end
end
