# app/jobs/process_chat_message_job.rb
# Background job to process LLM chat messages and broadcast response
class ProcessChatMessageJob < ApplicationJob
  queue_as :default

  def perform(message_id, chat_id, user_id)
    user = User.find(user_id)
    chat = Chat.find(chat_id)
    message = Message.find(message_id)

    # Set up context for the service
    context = chat.build_context(location: :dashboard)

    # Process the message through ChatCompletionService
    service = ChatCompletionService.new(chat, message, context)
    result = service.call

    if result.success?
      assistant_message = result.data
    else
      # Create error message if LLM fails
      Rails.logger.warn("Chat completion failed: #{result.errors.join(', ')}")
      assistant_message = Message.create_templated(
        chat: chat,
        template_type: "error",
        template_data: {
          message: "I encountered an issue processing your message. Please try again.",
          error_code: "CHAT_ERROR",
          details: result.errors.join(", ")
        }
      )
    end

    # Broadcast the response to all users viewing this chat
    broadcast_assistant_response(chat, assistant_message)
  rescue => e
    Rails.logger.error("ProcessChatMessageJob failed: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))

    # Notify user of the error
    chat = Chat.find(chat_id) rescue nil
    if chat
      error_message = Message.create_templated(
        chat: chat,
        template_type: "error",
        template_data: {
          message: "An unexpected error occurred while processing your message.",
          error_code: "SYSTEM_ERROR",
          details: e.message
        }
      )
      broadcast_assistant_response(chat, error_message)
    end
  end

  private

  def broadcast_assistant_response(chat, assistant_message)
    context = chat.build_context(location: :dashboard)

    Rails.logger.info("ProcessChatMessageJob: Broadcasting response for chat #{chat.id}")
    Rails.logger.info("ProcessChatMessageJob: Assistant message ID: #{assistant_message.id}, class: #{assistant_message.class}")

    begin
      # Broadcast via Turbo Streams to replace the loading indicator
      Turbo::StreamsChannel.broadcast_replace_to(
        "chat_#{chat.id}",
        target: "chat-loading-#{chat.id}",
        html: ApplicationController.render(
          partial: "chats/assistant_message_replacement",
          locals: {
            message: assistant_message,
            chat_context: context
          }
        )
      )
      Rails.logger.info("ProcessChatMessageJob: Broadcast sent successfully")
    rescue => e
      Rails.logger.error("ProcessChatMessageJob: Broadcast failed - #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))
    end
  end
end
