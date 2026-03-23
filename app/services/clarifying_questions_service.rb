# app/services/clarifying_questions_service.rb
# Displays structured clarifying questions as an interactive form in chat
# Works for product recommendations, planning refinement, or any conversation context

class ClarifyingQuestionsService < ApplicationService
  def initialize(chat:, questions:, context_title: nil)
    @chat = chat
    @questions = questions  # Array of {question, context, input_type, options}
    @context_title = context_title || "Please answer the following questions"
  end

  def call
    begin
      return failure(errors: ["No questions provided"]) if @questions.blank?

      Rails.logger.info("ClarifyingQuestionsService - Showing #{@questions.length} clarifying questions")

      # Create templated message with interactive form
      message = Message.create_templated(
        chat: @chat,
        template_type: "clarifying_questions",
        template_data: {
          questions: @questions,
          chat_id: @chat.id,
          context_title: @context_title
        }
      )

      @chat.update(last_message_at: Time.current)

      Rails.logger.info("ClarifyingQuestionsService - Clarifying questions form shown")

      # Broadcast the clarifying questions message to the chat via Turbo Stream
      broadcast_clarifying_questions_message(message)

      success(data: message)
    rescue StandardError => e
      Rails.logger.error("ClarifyingQuestionsService error: #{e.class} - #{e.message}")
      failure(errors: [ e.message ])
    end
  end

  private

  # Broadcast clarifying questions message via Turbo Stream
  def broadcast_clarifying_questions_message(message)
    begin
      Turbo::StreamsChannel.broadcast_append_to(
        "chat_#{@chat.id}",
        target: "chat-messages-#{@chat.id}",
        partial: "shared/chat_message",
        locals: { message: message, chat_context: @chat.chat_context }
      )
      Rails.logger.info("ClarifyingQuestionsService - Message broadcasted via Turbo Stream")
    rescue => e
      Rails.logger.warn("ClarifyingQuestionsService - Failed to broadcast message: #{e.message}")
      # Non-blocking - message still exists in DB
    end
  end
end
