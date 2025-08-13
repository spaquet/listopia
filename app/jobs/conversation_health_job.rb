# app/jobs/conversation_health_job.rb
class ConversationHealthJob < ApplicationJob
  queue_as :low_priority

  # Run every 30 minutes
  def perform
    Rails.logger.info "Starting conversation health monitoring sweep"

    health_results = {
      checked: 0,
      healed: 0,
      archived: 0,
      errors: 0,
      start_time: Time.current
    }

    begin
      # Find conversations that need attention
      problematic_chats = find_chats_needing_attention

      problematic_chats.find_each do |chat|
        health_results[:checked] += 1

        begin
          process_chat_health(chat, health_results)
        rescue => e
          Rails.logger.error "Error processing chat #{chat.id}: #{e.message}"
          health_results[:errors] += 1
        end
      end

      # Clean up old checkpoints and recovery contexts
      cleanup_old_recovery_data

      # Perform API health check
      perform_api_health_check

      log_health_results(health_results)

    rescue => e
      Rails.logger.error "Conversation health job failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end

  private

  def find_chats_needing_attention
    Chat.where(conversation_state: [ "error", "needs_cleanup" ])
        .or(Chat.where("last_stable_at < ? OR last_stable_at IS NULL", 6.hours.ago))
        .includes(:user, :messages, :tool_calls)
  end

  def process_chat_health(chat, health_results)
    state_manager = ChatStateManager.new(chat)

    Rails.logger.info "Checking health for chat #{chat.id} (user: #{chat.user_id})"

    # Get health metrics first
    metrics = state_manager.health_metrics

    # If health score is very low, consider archiving
    if metrics[:health_score] < 20 && chat.safe_for_aggressive_cleanup?
      archive_severely_corrupted_chat(chat)
      health_results[:archived] += 1
      return
    end

    # Attempt healing
    result = state_manager.validate_and_heal_state!

    case result[:status]
    when :healthy
      # Already healthy, just update timestamp
      chat.update_column(:last_stable_at, Time.current)

    when :healed
      Rails.logger.info "Healed chat #{chat.id}: #{result[:actions_taken].join(', ')}"
      health_results[:healed] += 1

    when :recovery_branch_created
      Rails.logger.info "Created recovery branch for chat #{chat.id}: #{result[:recovery_chat].id}"
      health_results[:healed] += 1

      # Notify user about the recovery (optional)
      notify_user_of_recovery(chat, result[:recovery_chat]) if should_notify_user?(chat)
    end

  rescue ChatStateManager::StateCorruptionError => e
    Rails.logger.warn "State corruption in chat #{chat.id}: #{e.message}"

    if chat.safe_for_aggressive_cleanup?
      archive_severely_corrupted_chat(chat)
      health_results[:archived] += 1
    else
      # Mark for manual review
      chat.update_column(:conversation_state, "error")
    end

  rescue => e
    Rails.logger.error "Failed to heal chat #{chat.id}: #{e.message}"
    health_results[:errors] += 1
  end

  def archive_severely_corrupted_chat(chat)
    Rails.logger.info "Archiving severely corrupted chat #{chat.id}"

    original_title = chat.title
    chat.update!(
      status: "archived",
      title: "#{original_title} (Auto-Archived - Corrupted #{Time.current.strftime('%m/%d')})",
      conversation_state: "error"
    )

    # Create a fresh chat for the user if they don't have an active one
    unless chat.user.chats.status_active.exists?
      fresh_chat = chat.user.chats.create!(
        title: "Chat #{Time.current.strftime('%m/%d %H:%M')}",
        status: "active",
        conversation_state: "stable",
        model_id: chat.model_id || Rails.application.config.mcp.model,
        last_stable_at: Time.current
      )

      Rails.logger.info "Created fresh chat #{fresh_chat.id} for user #{chat.user_id}"
    end
  end

  def cleanup_old_recovery_data
    Rails.logger.info "Cleaning up old recovery data"

    # Clean up old recovery contexts (older than 24 hours)
    old_contexts = RecoveryContext.where("created_at < ?", 24.hours.ago)
    old_count = old_contexts.count
    old_contexts.destroy_all

    Rails.logger.info "Cleaned up #{old_count} old recovery contexts" if old_count > 0

    # Clean up old checkpoints (older than 7 days)
    old_checkpoints = ConversationCheckpoint.where("created_at < ?", 7.days.ago)
    checkpoint_count = old_checkpoints.count
    old_checkpoints.destroy_all

    Rails.logger.info "Cleaned up #{checkpoint_count} old checkpoints" if checkpoint_count > 0

    # Clean up checkpoints from deleted chats
    orphaned_checkpoints = ConversationCheckpoint.left_joins(:chat).where(chats: { id: nil })
    orphaned_count = orphaned_checkpoints.count
    orphaned_checkpoints.destroy_all

    Rails.logger.info "Cleaned up #{orphaned_count} orphaned checkpoints" if orphaned_count > 0
  end

  def perform_api_health_check
    Rails.logger.info "Performing API health check"

    begin
      resilient_llm = ResilientRubyLlmService.new
      health_result = resilient_llm.perform_health_check!

      if health_result[:healthy]
        Rails.logger.info "API health check passed (#{health_result[:response_time]}s)"
      else
        Rails.logger.warn "API health check failed: #{health_result[:message]}"

        # Optionally send alert to monitoring system
        send_health_alert(health_result) if defined?(Bugsnag)
      end

    rescue => e
      Rails.logger.error "API health check error: #{e.message}"
    end
  end

  def should_notify_user?(chat)
    # Only notify for recently active users
    chat.user.current_sign_in_at && chat.user.current_sign_in_at > 24.hours.ago
  end

  def notify_user_of_recovery(original_chat, recovery_chat)
    # This could send an email or in-app notification
    # For now, just log it
    Rails.logger.info "Would notify user #{original_chat.user_id} about chat recovery: #{original_chat.id} -> #{recovery_chat.id}"

    # Example: Could enqueue a notification job
    # UserNotificationJob.perform_later(
    #   original_chat.user_id,
    #   :chat_recovered,
    #   { original_chat_id: original_chat.id, recovery_chat_id: recovery_chat.id }
    # )
  end

  def send_health_alert(health_result)
    return unless defined?(Bugsnag)

    Bugsnag.notify("API Health Check Failed") do |report|
      report.severity = "warning"
      report.add_metadata(:health_check, health_result)
    end
  end

  def log_health_results(results)
    duration = Time.current - results[:start_time]

    Rails.logger.info <<~LOG
      Conversation health monitoring completed:
      - Duration: #{duration.round(2)}s
      - Chats checked: #{results[:checked]}
      - Chats healed: #{results[:healed]}
      - Chats archived: #{results[:archived]}
      - Errors encountered: #{results[:errors]}
    LOG
  end
end
