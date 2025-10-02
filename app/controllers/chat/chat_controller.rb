# app/controllers/chat/chat_controller.rb
class Chat::ChatController < ApplicationController
  include ListBroadcasting

  before_action :authenticate_user!

  def create_message
    message_content = params[:message]
    current_page = params[:current_page]
    context = params[:context] || {}

    # Use the AI Agent service with moderation
    service = AiAgentMcpService.new(
      user: current_user,
      context: build_chat_context.merge(context)
    )

    result = service.process_message(message_content)

    # Handle real-time broadcasting for created lists
    if result[:lists_created].any?
      result[:lists_created].each do |list|
        broadcast_list_creation(list)
        broadcast_dashboard_updates(list)
      end
    end

    # CRITICAL FIX: Get BOTH messages from the result
    # The service returns the chat which has both messages
    chat = service.chat
    user_message = chat.messages.where(role: "user", content: message_content).order(created_at: :desc).first
    assistant_message = result[:message]

    respond_to do |format|
      format.turbo_stream do
        # Render BOTH the user message and assistant response
        streams = []

        # Append user message first
        if user_message
          streams << turbo_stream.append("chat-messages",
            partial: "chat/message",
            locals: { message: user_message }
          )
        end

        # Then append assistant response
        streams << turbo_stream.append("chat-messages",
          partial: "chat/message",
          locals: { message: assistant_message }
        )

        render turbo_stream: streams
      end
      format.json { render json: result }
    end

  rescue => e
    Rails.logger.error "Chat controller error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    error_message = if Rails.env.development?
      "Error: #{e.message}"
    else
      "I encountered an issue. Please try again."
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append("chat-messages",
          partial: "chat/error_message",
          locals: { error: error_message }
        )
      end
      format.json { render json: { error: error_message }, status: :unprocessable_entity }
    end
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

  def build_chat_context
    {
      page: "#{controller_name}##{action_name}",
      current_page: params[:current_page],
      user_id: current_user.id,
      total_lists: current_user.accessible_lists.count,
      current_time: Time.current.iso8601
    }
  end
end
