# app/controllers/chat/chat_controller.rb
class Chat::ChatController < ApplicationController
    include ListBroadcasting  # real-time updates

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

      # Handle real-time broadcasting for created lists using existing patterns
      if result[:lists_created].any?
        result[:lists_created].each do |list|
          # Use the existing broadcast_list_creation method from ListBroadcasting concern
          broadcast_list_creation(list)

          # Use the existing broadcast_dashboard_updates method from ListBroadcasting concern
          broadcast_dashboard_updates(list)
        end
      end

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            # Update chat messages (works for both normal and moderation blocked messages)
            turbo_stream.append("chat-messages",
              partial: "chat/message",
              locals: { message: result[:message] }
            )
            # NOTE: We don't need manual lists_turbo_streams anymore because
            # broadcast_list_creation handles real-time updates to all connected users
          ]
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
        current_time: Time.current.iso8601,
        # Use permit! carefully for dynamic context (as noted in original code)
        **params.fetch(:context, {}).permit!.to_h
      }
    end

    def build_success_message(result)
      lists_count = result[:lists_created].count
      items_count = result[:items_created].count

      if lists_count == 1 && items_count > 0
        "Created '#{result[:lists_created].first.title}' with #{items_count} items"
      elsif lists_count > 1
        "Created #{lists_count} lists with #{items_count} total items"
      elsif lists_count == 1
        "Created '#{result[:lists_created].first.title}'"
      else
        "Successfully processed your request"
      end
    end
end
