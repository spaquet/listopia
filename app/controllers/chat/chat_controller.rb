# app/controllers/chat/chat_controller.rb
class Chat::ChatController < ApplicationController
  include ListBroadcasting

  before_action :authenticate_user!

  def create_message
    message_content = params[:message]
    current_page = params[:current_page]
    context = params[:context] || {}

    # Determine if this is from dashboard
    from_dashboard = current_page == "dashboard#index"
    target_id = from_dashboard ? "dashboard-chat-messages" : "chat-messages"

    # Use the AI Agent service with moderation
    service = AiAgentMcpService.new(
      user: current_user,
      context: build_chat_context.merge(context.to_unsafe_h)
    )

    result = service.process_message(message_content)

    # Handle real-time broadcasting for created lists
    if result[:lists_created].any?
      result[:lists_created].each do |list|
        broadcast_list_creation(list)
        broadcast_dashboard_updates(list)
      end
    end

    # Get BOTH messages from the chat
    chat = service.chat
    user_message = chat.messages.where(role: "user", content: message_content)
                      .order(created_at: :desc).first
    assistant_message = result[:message]

    # Choose the appropriate message partial based on source
    message_partial = from_dashboard ? "dashboard/chat_message" : "chat/message"

    respond_to do |format|
      format.turbo_stream do
        streams = []

        # Append user message first
        if user_message
          streams << turbo_stream.append(target_id,
            partial: message_partial,
            locals: {
              message: user_message,
              lists_created: []  # User messages don't create lists
            }
          )
        end

        # Then append assistant response with any created lists
        streams << turbo_stream.append(target_id,
          partial: message_partial,
          locals: {
            message: assistant_message,
            lists_created: result[:lists_created]  # Pass created lists to partial
          }
        )

        render turbo_stream: streams
      end
      format.json { render json: result }
    end

  rescue => e
    Rails.logger.error "Chat controller error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    error_text = if Rails.env.development?
      "Error: #{e.message}"
    else
      "I encountered an issue. Please try again."
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append(target_id,
          partial: "chat/error_message",
          locals: { error_message: error_text }
        )
      end
      format.json { render json: { error: error_text }, status: :unprocessable_entity }
    end
  end

  def load_dashboard_history
    @chat = current_user.current_chat

    # Inline the query - no need for tool_calls in dashboard view
    @messages = if @chat
      @chat.messages.displayable
          .includes(:user)
          .order(created_at: :desc)
          .limit(50)
          .reverse
    else
      []
    end

    respond_to do |format|
      format.turbo_stream do
        streams = []

        # Replace the messages container content
        streams << turbo_stream.replace("dashboard-chat-messages",
          partial: "dashboard/chat_history",
          locals: { messages: @messages }
        )

        # Show compact suggestions if there are messages
        if @messages.any?
          streams << turbo_stream.update("dashboard-suggestions-compact",
            "<div id='dashboard-suggestions-compact' class='flex-shrink-0 px-6 py-3 border-t border-gray-100 bg-gray-50'>
              <!-- suggestions content will be rendered by the partial -->
            </div>")
          streams << turbo_stream.remove("dashboard-chat-welcome") if @messages.any?
        end

        render turbo_stream: streams
      end
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
