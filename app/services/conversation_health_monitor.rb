# app/services/conversation_health_monitor.rb
class ConversationHealthMonitor
  include ActiveSupport::Benchmarkable

  def self.check_all_active_chats
    new.check_all_active_chats
  end

  def initialize
    @logger = Rails.logger
    @metrics = {}
  end

  def check_all_active_chats
    @logger.info "Starting conversation health check for all active chats"

    benchmark "Conversation health check" do
      active_chats = Chat.status_active.includes(:messages, :tool_calls)

      @metrics = {
        total_chats: active_chats.count,
        healthy_chats: 0,
        chats_with_issues: 0,
        repaired_chats: 0,
        failed_repairs: 0,
        orphaned_messages_cleaned: 0
      }

      active_chats.find_each do |chat|
        check_chat_health(chat)
      end

      log_summary
    end
  end

  def check_chat_health(chat)
    begin
      conversation_manager = ConversationStateManager.new(chat)
      conversation_manager.ensure_conversation_integrity!

      @metrics[:healthy_chats] += 1

    rescue ConversationStateManager::ConversationError => e
      @logger.warn "Chat #{chat.id} has conversation issues: #{e.message}"
      @metrics[:chats_with_issues] += 1

      # Attempt repair
      if attempt_repair(chat, conversation_manager)
        @metrics[:repaired_chats] += 1
      else
        @metrics[:failed_repairs] += 1
        alert_severe_conversation_issue(chat, e)
      end
    end
  end

  def attempt_repair(chat, conversation_manager)
    begin
      # Try to repair the conversation
      conversation_manager.send(:attempt_conversation_repair!)

      # Clean up orphaned messages
      orphaned_count = chat.cleanup_orphaned_messages!
      @metrics[:orphaned_messages_cleaned] += orphaned_count

      # Re-validate after repair
      conversation_manager.ensure_conversation_integrity!

      @logger.info "Successfully repaired conversation for chat #{chat.id}"
      true

    rescue => repair_error
      @logger.error "Failed to repair chat #{chat.id}: #{repair_error.message}"
      false
    end
  end

  def alert_severe_conversation_issue(chat, error)
    # Log severe issues that couldn't be auto-repaired
    @logger.error "SEVERE: Chat #{chat.id} conversation cannot be repaired: #{error.message}"

    # In production, you might want to:
    # - Send alerts to monitoring systems (Bugsnag, Sentry, etc.)
    # - Archive the problematic chat
    # - Notify the user if appropriate

    # For now, we'll archive severely broken chats
    if should_archive_broken_chat?(chat, error)
      archive_broken_chat(chat, error)
    end

    # Send to monitoring service if configured
    if defined?(Bugsnag)
      Bugsnag.notify(error) do |report|
        report.add_metadata(:chat, {
          id: chat.id,
          user_id: chat.user_id,
          message_count: chat.messages.count,
          tool_calls_count: chat.tool_calls.count,
          status: chat.status
        })
      end
    end
  end

  def should_archive_broken_chat?(chat, error)
    # Archive if:
    # 1. Chat has multiple severe errors
    # 2. Chat is old and likely corrupted
    # 3. Chat has excessive orphaned messages

    chat.created_at < 7.days.ago ||
    chat.orphaned_tool_messages.count > 5 ||
    error.is_a?(ConversationStateManager::MalformedToolResponseError)
  end

  def archive_broken_chat(chat, error)
    original_title = chat.title
    chat.update!(
      status: "archived",
      title: "#{original_title} (Auto-archived: #{error.class.name.demodulize})",
      metadata: (chat.metadata || {}).merge({
        archived_reason: "conversation_integrity_failure",
        archived_at: Time.current,
        original_error: error.message
      })
    )

    @logger.info "Archived broken chat #{chat.id}: #{original_title}"
  end

  def log_summary
    @logger.info "Conversation health check complete:"
    @logger.info "  Total chats checked: #{@metrics[:total_chats]}"
    @logger.info "  Healthy chats: #{@metrics[:healthy_chats]}"
    @logger.info "  Chats with issues: #{@metrics[:chats_with_issues]}"
    @logger.info "  Successfully repaired: #{@metrics[:repaired_chats]}"
    @logger.info "  Failed repairs: #{@metrics[:failed_repairs]}"
    @logger.info "  Orphaned messages cleaned: #{@metrics[:orphaned_messages_cleaned]}"

    # Calculate health percentage
    if @metrics[:total_chats] > 0
      health_percentage = ((@metrics[:healthy_chats] + @metrics[:repaired_chats]).to_f / @metrics[:total_chats] * 100).round(2)
      @logger.info "  Overall health: #{health_percentage}%"

      # Alert if health is below threshold
      if health_percentage < 95.0
        @logger.warn "ALERT: Conversation health below 95% (#{health_percentage}%)"
      end
    end
  end

  # Check a specific chat's health
  def self.check_chat(chat_id)
    chat = Chat.find(chat_id)
    monitor = new
    monitor.check_chat_health(chat)
  end

  # Run health check as a background job
  def self.schedule_health_check
    ConversationHealthCheckJob.perform_later
  end

  private

  def logger
    @logger
  end
end

# Background job for regular health checks
class ConversationHealthCheckJob < ApplicationJob
  queue_as :low_priority

  def perform
    ConversationHealthMonitor.check_all_active_chats
  end
end

# Rake task for manual health checks
# lib/tasks/conversation_health.rake
namespace :conversation do
  desc "Check health of all active conversations"
  task health_check: :environment do
    ConversationHealthMonitor.check_all_active_chats
  end

  desc "Check health of a specific chat"
  task :check_chat, [ :chat_id ] => :environment do |t, args|
    chat_id = args[:chat_id]
    raise "Chat ID required" unless chat_id

    ConversationHealthMonitor.check_chat(chat_id)
  end

  desc "Repair a specific chat"
  task :repair_chat, [ :chat_id ] => :environment do |t, args|
    chat_id = args[:chat_id]
    raise "Chat ID required" unless chat_id

    chat = Chat.find(chat_id)

    begin
      chat.repair_conversation!
      puts "✅ Successfully repaired chat #{chat_id}"
    rescue => e
      puts "❌ Failed to repair chat #{chat_id}: #{e.message}"
    end
  end

  desc "Clean up orphaned messages across all chats"
  task cleanup_orphaned: :environment do
    total_cleaned = 0

    Chat.status_active.find_each do |chat|
      cleaned = chat.cleanup_orphaned_messages!
      total_cleaned += cleaned
    end

    puts "🧹 Cleaned up #{total_cleaned} orphaned messages across all chats"
  end
end
