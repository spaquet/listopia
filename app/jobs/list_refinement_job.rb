# app/jobs/list_refinement_job.rb
#
# Background job for generating list refinement questions
# PHASE 2 OPTIMIZATION: Don't block user response waiting for refinement
#
# Instead of:
#   1. Create list
#   2. Generate refinement questions (2-3 seconds WAIT)
#   3. Return response
#
# Now does:
#   1. Create list
#   2. Return response immediately
#   3. Refinement job runs in background
#   4. Push questions via Turbo Stream when ready

class ListRefinementJob < ApplicationJob
  queue_as :default

  def perform(list_id, chat_id)
    list = List.find(list_id)
    chat = Chat.find(chat_id)

    Rails.logger.info("ListRefinementJob started for list: #{list.id}, chat: #{chat.id}")

    # Generate refinement questions
    refinement_service = ListRefinementService.new(
      list_title: list.title,
      category: list.category,
      items: list.list_items.pluck(:title),
      context: chat.build_context,
      nested_sublists: [],
      planning_domain: chat.metadata&.dig("planning_domain")
    )

    result = refinement_service.call

    if result.success?
      refinement_data = result.data
      questions = refinement_data[:questions] || []

      if questions.present?
        # Store in chat metadata for state management
        chat.metadata ||= {}
        chat.metadata["pending_list_refinement"] = {
          list_id: list.id,
          questions: questions,
          context: refinement_data[:refinement_context],
          generated_at: Time.current.iso8601
        }
        chat.save!

        Rails.logger.info("ListRefinementJob - Generated #{questions.length} refinement questions for list: #{list.id}")

        # Push refinement questions via Turbo Stream
        broadcast_refinement_questions(chat, list, questions)
      else
        Rails.logger.info("ListRefinementJob - No refinement questions needed for list: #{list.id}")
      end
    else
      Rails.logger.warn("ListRefinementJob - Refinement service failed for list: #{list.id}")
    end
  rescue => e
    Rails.logger.error("ListRefinementJob failed: #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}")
    # Let Solid Queue handle retries
    raise
  end

  private

  def broadcast_refinement_questions(chat, list, questions)
    # Broadcast a Turbo Stream action to append refinement questions
    # The view will handle rendering these questions
    Turbo::StreamsChannel.broadcast_action_to(
      [ "chat", chat.id ],
      action: :append,
      target: "chat-messages",
      partial: "chats/refinement_questions_message",
      locals: {
        list: list,
        questions: questions,
        chat: chat
      }
    )
  rescue => e
    Rails.logger.error("Failed to broadcast refinement questions: #{e.message}")
    # Non-blocking - user still sees the list, just won't get refinement questions
  end
end
