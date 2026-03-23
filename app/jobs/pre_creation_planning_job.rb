# app/jobs/pre_creation_planning_job.rb
#
# Background job for generating pre-creation planning clarifying questions
# OPTIMIZATION: Non-blocking question generation for complex list requests
#
# Instead of:
#   1. User submits message
#   2. Service generates questions (3-5s LLM call WAIT)
#   3. Return response
#
# Now does:
#   1. User submits message
#   2. Return "analyzing request..." message immediately
#   3. Background job generates questions (LLM call)
#   4. Push questions via Turbo Stream when ready

class PreCreationPlanningJob < ApplicationJob
  queue_as :default

  def perform(chat_id, list_title, category, items, nested_lists, planning_domain, location = :dashboard)
    chat = Chat.find(chat_id)

    Rails.logger.info("PreCreationPlanningJob started for chat: #{chat.id}, list: #{list_title}, location: #{location}")

    # Generate clarifying questions
    refinement = ListRefinementService.new(
      list_title: list_title,
      category: category,
      items: items,
      nested_sublists: nested_lists,
      planning_domain: planning_domain,
      context: ChatUiContext.new(
        chat: chat,
        user: chat.user,
        organization: chat.organization,
        location: location
      )
    )

    result = refinement.call

    if result.success? && result.data[:needs_refinement]
      questions = result.data[:questions] || []

      if questions.present?
        Rails.logger.info("PreCreationPlanningJob - Generated #{questions.length} questions for chat: #{chat.id}")

        # Update chat metadata with questions
        chat.metadata ||= {}
        chat.metadata["pending_pre_creation_planning"] = {
          extracted_params: { title: list_title, category: category, items: items },
          questions_asked: questions.map { |q| q["question"] },
          refinement_context: result.data[:refinement_context],
          intent: "create_list",
          status: "ready"
        }
        chat.save!

        # Broadcast the form via Turbo Stream
        broadcast_planning_form(chat, questions, list_title)
        return
      end
    end

    # If no questions generated, just mark as done
    Rails.logger.warn("PreCreationPlanningJob - No questions generated for chat: #{chat.id}")
    chat.metadata ||= {}
    chat.metadata.delete("pending_pre_creation_planning")
    chat.save!
  rescue => e
    Rails.logger.error("PreCreationPlanningJob failed: #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}")
    # Let Sidekiq handle retries
    raise
  end

  private

  def broadcast_planning_form(chat, questions, list_title)
    # Broadcast a Turbo Stream action to replace the "analyzing request..." message
    # with the actual pre-creation planning form
    template_data = {
      questions: questions,
      chat_id: chat.id,
      list_title: list_title
    }

    Turbo::StreamsChannel.broadcast_action_to(
      [ "chat", chat.id ],
      action: :append,
      target: "chat-messages",
      partial: "chats/pre_creation_planning_message",
      locals: {
        questions: questions,
        chat: chat,
        list_title: list_title
      }
    )
  rescue => e
    Rails.logger.error("Failed to broadcast pre-creation planning form: #{e.message}")
    # Non-blocking - user still has chat, just won't see the form immediately
  end
end
