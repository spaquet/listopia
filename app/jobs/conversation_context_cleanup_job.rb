# app/jobs/conversation_context_cleanup_job.rb
class ConversationContextCleanupJob < ApplicationJob
  queue_as :low_priority

  # Run daily to clean up old conversation contexts
  def perform
    start_time = Time.current

    Rails.logger.info "Starting conversation context cleanup"

    begin
      # Use the ConversationContextManager's cleanup method
      cleanup_result = ConversationContextManager.cleanup_expired_contexts!

      # Additional cleanup for orphaned contexts
      orphaned_result = cleanup_orphaned_contexts

      # Clean up contexts for deleted entities
      entity_cleanup_result = cleanup_deleted_entity_contexts

      total_processing_time = Time.current - start_time

      Rails.logger.info "Context cleanup completed successfully in #{total_processing_time.round(2)}s"
      Rails.logger.info "Cleanup summary: #{cleanup_result[:total]} expired, #{orphaned_result} orphaned, #{entity_cleanup_result} deleted entities"

      # Report metrics if monitoring system exists
      report_cleanup_metrics(cleanup_result, orphaned_result, entity_cleanup_result, total_processing_time)

    rescue => e
      Rails.logger.error "Context cleanup job failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Re-raise to let the job queue handle retries
      raise e
    end
  end

  private

  def cleanup_orphaned_contexts
    # Find contexts where the user no longer exists
    orphaned_user_contexts = ConversationContext
      .left_joins(:user)
      .where(users: { id: nil })

    orphaned_count = orphaned_user_contexts.count
    orphaned_user_contexts.delete_all

    # Find contexts where the chat no longer exists (for contexts with chat_id)
    orphaned_chat_contexts = ConversationContext
      .where.not(chat_id: nil)
      .left_joins(:chat)
      .where(chats: { id: nil })

    orphaned_chat_count = orphaned_chat_contexts.count
    orphaned_chat_contexts.delete_all

    total_orphaned = orphaned_count + orphaned_chat_count

    if total_orphaned > 0
      Rails.logger.info "Cleaned up #{total_orphaned} orphaned contexts (#{orphaned_count} users, #{orphaned_chat_count} chats)"
    end

    total_orphaned
  end

  def cleanup_deleted_entity_contexts
    deleted_count = 0

    # Check List contexts
    list_contexts = ConversationContext.where(entity_type: "List")
    list_contexts.find_each do |context|
      unless List.exists?(context.entity_id)
        context.destroy
        deleted_count += 1
      end
    end

    # Check ListItem contexts
    item_contexts = ConversationContext.where(entity_type: "ListItem")
    item_contexts.find_each do |context|
      unless ListItem.exists?(context.entity_id)
        context.destroy
        deleted_count += 1
      end
    end

    # Check Chat contexts (separate from orphaned chat cleanup)
    chat_contexts = ConversationContext.where(entity_type: "Chat")
    chat_contexts.find_each do |context|
      unless Chat.exists?(context.entity_id)
        context.destroy
        deleted_count += 1
      end
    end

    if deleted_count > 0
      Rails.logger.info "Cleaned up #{deleted_count} contexts for deleted entities"
    end

    deleted_count
  end

  def report_cleanup_metrics(cleanup_result, orphaned_count, deleted_entities_count, processing_time)
    # This method can be extended to report to monitoring systems
    # like DataDog, New Relic, or custom metrics collection

    metrics = {
      expired_contexts: cleanup_result[:expired],
      old_contexts: cleanup_result[:old],
      irrelevant_contexts: cleanup_result[:irrelevant],
      orphaned_contexts: orphaned_count,
      deleted_entity_contexts: deleted_entities_count,
      total_cleaned: cleanup_result[:total] + orphaned_count + deleted_entities_count,
      processing_time_seconds: processing_time
    }

    # Example: Report to Rails logger (can be extended)
    Rails.logger.info "Context cleanup metrics: #{metrics.to_json}"

    # If you have a metrics service, report here:
    # MetricsService.report('conversation_context_cleanup', metrics)
  end
end
