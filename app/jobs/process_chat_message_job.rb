# app/jobs/process_chat_message_job.rb
# Background job to process LLM chat messages and route to appropriate handler
# Dispatches to agents for create_list intent, otherwise uses ChatCompletionService
class ProcessChatMessageJob < ApplicationJob
  queue_as :default

  def perform(message_id, chat_id, user_id)
    user = User.find(user_id)
    chat = Chat.find(chat_id)
    message = Message.find(message_id)

    # If user just answered clarifying questions, proceed to agent
    if chat.metadata["pending_list_intent"].present?
      return trigger_list_creator_with_answers(chat, message, user)
    end

    # Detect intent from the user's message
    combined_result = CombinedIntentComplexityService.new(
      user_message: message,
      chat: chat,
      user: user,
      organization: chat.organization
    ).call

    if combined_result.success? && combined_result.data[:intent] == "create_list"
      handle_list_creation_intent(chat, message, user, combined_result.data)
    else
      # Route to ChatCompletionService for other intents
      process_with_completion_service(chat, message, user)
    end
  rescue => e
    Rails.logger.error("ProcessChatMessageJob failed: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.first(10).join("\n"))

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

  def handle_list_creation_intent(chat, message, user, combined_data)
    is_complex = combined_data[:is_complex] || false

    if is_complex
      # For complex requests, show clarifying questions first
      show_clarifying_questions(chat, message, user, combined_data)
    else
      # For simple requests, trigger agent immediately
      trigger_list_creator_agent(chat, message.content, user, combined_data)
    end
  end

  def show_clarifying_questions(chat, message, user, combined_data)
    # Generate clarifying questions based on planning domain
    questions_service = ListCreationQuestionsService.new(
      user_message_content: message.content,
      planning_domain: combined_data[:planning_domain] || "general",
      is_complex: true
    )
    questions_result = questions_service.call

    if questions_result.success? && questions_result.data.present?
      questions = questions_result.data

      # Show clarifying questions form
      clarity_service = ClarifyingQuestionsService.new(
        chat: chat,
        questions: questions,
        context_title: "Please help me understand your request better"
      )
      clarity_service.call

      # Store state: indicate we're waiting for answers
      chat.update(metadata: chat.metadata.merge({
        "pending_list_intent" => {
          "original_message" => message.content,
          "planning_domain" => combined_data[:planning_domain],
          "parameters" => combined_data[:parameters] || {}
        }
      }))

      # Replace loading indicator with questions message
      broadcast_assistant_response(chat, Message.last)
    else
      # No questions needed, proceed directly to agent
      trigger_list_creator_agent(chat, message.content, user, combined_data)
    end
  end

  def trigger_list_creator_with_answers(chat, message, user)
    pending = chat.metadata["pending_list_intent"]
    original_message = pending["original_message"]

    # Compose the full input: original request + answers
    input = "Original request: #{original_message}\n\nUser answered clarifying questions:\n#{message.content}"

    # Clear pending state
    chat.update(metadata: chat.metadata.except("pending_list_intent"))

    # Trigger the agent with the combined input
    trigger_list_creator_agent(chat, input, user, pending["parameters"] || {})
  end

  def trigger_list_creator_agent(chat, input, user, combined_data = {})
    # Find or get list-creator agent
    agent = AiAgent.find_by(slug: "list-creator", scope: :system_agent)
    unless agent
      Rails.logger.error("List creator agent not found")
      return process_with_completion_service(chat, Message.new(content: input), user)
    end

    # Show "agent is running" indicator immediately
    agent_running_msg = Message.create_templated(
      chat: chat,
      template_type: "agent_running",
      template_data: {
        run_id: SecureRandom.uuid,  # Placeholder, will be replaced
        agent_name: "List Creator",
        status: "running",
        message: "Creating your list..."
      }
    )

    # Broadcast the loading indicator
    broadcast_assistant_response(chat, agent_running_msg)

    # Trigger the agent
    trigger_result = AgentTriggerService.trigger_manual(
      agent: agent,
      user: user,
      input: input,
      invocable: chat
    )

    if trigger_result.success?
      run = trigger_result.data[:run]
      # Store message ID in run so broadcast knows where to update
      params = run.input_parameters.is_a?(Hash) ? run.input_parameters : {}
      run.update(input_parameters: params.merge({
        "chat_message_id" => agent_running_msg.id
      }))
    else
      Rails.logger.error("Failed to trigger list creator agent: #{trigger_result.message}")
      error_msg = Message.create_assistant(
        chat: chat,
        content: "Failed to create list. Please try again."
      )
      broadcast_assistant_response(chat, error_msg)
    end
  end

  def process_with_completion_service(chat, message, user)
    context = chat.build_ui_context(location: :dashboard)
    service = ChatCompletionService.new(chat, message, context)
    result = service.call

    if result.success?
      assistant_message = result.data
    else
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

    broadcast_assistant_response(chat, assistant_message)
  end

  def broadcast_assistant_response(chat, assistant_message)
    context = chat.build_ui_context(location: :dashboard)

    Rails.logger.info("ProcessChatMessageJob: Broadcasting response for chat #{chat.id}")

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
