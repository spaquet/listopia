# app/controllers/chat/chat_controller.rb
class Chat::ChatController < ApplicationController
  include ListBroadcasting

  def create_message
    service = McpService.new(user: current_user, context: build_chat_context)
    result = service.process_message(params[:message])

    # Build turbo stream response
    streams = []

    # Add chat message
    streams << turbo_stream.append("chat-messages",
      partial: "chat/assistant_message",
      locals: { message: result[:message].content }
    )

    # Use existing broadcasting methods for real-time updates
    if result[:lists_created].any?
      result[:lists_created].each do |list|
        # Use the existing broadcast_list_creation method
        broadcast_list_creation(list)

        # Use the existing broadcast_dashboard_updates method
        broadcast_dashboard_updates(list)
      end
    end

    render turbo_stream: streams
  rescue => e
    Rails.logger.error "Controller error: #{e.message}"

    render turbo_stream: turbo_stream.append("chat-messages",
      partial: "chat/assistant_message",
      locals: { message: "Sorry, I encountered an error. Please try again." }
    )
  end

  def load_history
    @chat = current_user.current_chat
    @messages = @chat&.latest_messages_with_includes

    render turbo_stream: turbo_stream.replace("chat-messages",
      partial: "chat/messages_history",
      locals: { messages: @messages || [] }
    )
  end

  private

  # TODO: Security - Replace permit! with specific allowed keys for mass assignment
  # This is a temporary solution to allow dynamic context passing from the frontend
  # Long-term: Define exact permitted context keys based on application needs
  def build_chat_context
    @context = {
      page: "#{controller_name}##{action_name}",
      current_page: params[:current_page],
      **params.fetch(:context, {}).permit!.to_h # brakeman:ignore
    }
  end
end
