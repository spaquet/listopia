# app/jobs/mcp_chat_job.rb
class McpChatJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(user_id, message, context = {})
    user = User.find(user_id)

    mcp_service = McpService.new(user: user, context: context)
    response = mcp_service.process_message(message)

    # Broadcast response via Turbo Streams
    broadcast_chat_response(user, response)

  rescue McpService::AuthorizationError => e
    broadcast_chat_response(user, "I'm sorry, but #{e.message.downcase}. Please check your permissions and try again.")
  rescue => e
    Rails.logger.error "MCP Job Error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    broadcast_chat_response(user, "I encountered an error processing your request. Please try again.")
  end

  private

  def broadcast_chat_response(user, message)
    # Broadcast to user's chat stream
    ActionCable.server.broadcast(
      "chat_#{user.id}",
      {
        type: "assistant_message",
        message: message,
        timestamp: Time.current.iso8601
      }
    )
  end
end
