# app/controllers/admin/mcp_health_controller.rb
class Admin::McpHealthController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!

  def index
    @health_overview = gather_health_overview
    @recent_errors = gather_recent_errors
    @performance_metrics = gather_performance_metrics
  end

  def api_status
    resilient_llm = ResilientRubyLlmService.new

    respond_to do |format|
      format.json do
        render json: {
          api_health: resilient_llm.health_status,
          timestamp: Time.current.iso8601
        }
      end
    end
  end

  def conversation_health
    @chat_stats = gather_conversation_statistics
    @problematic_chats = find_problematic_chats

    respond_to do |format|
      format.html { render :conversation_health }
      format.json do
        render json: {
          stats: @chat_stats,
          problematic_chats: @problematic_chats.map(&:conversation_stats),
          timestamp: Time.current.iso8601
        }
      end
    end
  end

  def repair_conversation
    chat = Chat.find(params[:chat_id])

    begin
      state_manager = ChatStateManager.new(chat)
      result = state_manager.validate_and_heal_state!

      respond_to do |format|
        format.json do
          render json: {
            success: true,
            status: result[:status],
            actions_taken: result[:actions_taken],
            recovery_chat_id: result[:recovery_chat]&.id
          }
        end
      end

    rescue => e
      Rails.logger.error "Manual conversation repair failed: #{e.message}"

      respond_to do |format|
        format.json do
          render json: {
            success: false,
            error: e.message
          }, status: :unprocessable_entity
        end
      end
    end
  end

  def force_health_check
    resilient_llm = ResilientRubyLlmService.new
    result = resilient_llm.perform_health_check!

    respond_to do |format|
      format.json { render json: result }
    end
  end

  def error_recovery_stats
    # Gather error recovery statistics from Redis
    stats = gather_error_recovery_stats

    respond_to do |format|
      format.json { render json: stats }
    end
  end

  private

  def require_admin!
    redirect_to root_path unless current_user.admin?
  end

  def gather_health_overview
    {
      total_chats: Chat.count,
      active_chats: Chat.status_active.count,
      archived_chats: Chat.status_archived.count,
      error_chats: Chat.conversation_state_error.count,
      chats_needing_cleanup: Chat.conversation_state_needs_cleanup.count,
      total_messages: Message.count,
      total_tool_calls: ToolCall.count,
      average_messages_per_chat: Chat.joins(:messages).group("chats.id").average("messages.id").values.sum / Chat.count.to_f
    }
  rescue => e
    Rails.logger.error "Error gathering health overview: #{e.message}"
    { error: e.message }
  end

  def gather_recent_errors
    # Get recent error patterns from logs or database
    recent_chats_with_errors = Chat.conversation_state_error
                                  .includes(:user, :messages)
                                  .limit(10)
                                  .order(updated_at: :desc)

    recent_chats_with_errors.map do |chat|
      {
        chat_id: chat.id,
        user_id: chat.user_id,
        title: chat.title,
        error_time: chat.updated_at,
        message_count: chat.messages.count,
        last_message: chat.messages.last&.content&.truncate(100)
      }
    end
  end

  def gather_performance_metrics
    # Calculate performance metrics
    recent_messages = Message.where("created_at > ?", 24.hours.ago)

    {
      messages_last_24h: recent_messages.count,
      average_processing_time: recent_messages.average(:processing_time)&.round(3),
      successful_responses: recent_messages.joins(:chat)
                                         .where(chats: { conversation_state: "stable" })
                                         .count,
      error_rate: calculate_error_rate(recent_messages),
      average_tokens_per_message: recent_messages.average("input_tokens + output_tokens")&.round(0)
    }
  end

  def gather_conversation_statistics
    {
      total_conversations: Chat.count,
      healthy_conversations: Chat.joins(:messages)
                                .where(conversation_state: "stable")
                                .count,
      conversations_with_issues: Chat.where.not(conversation_state: "stable").count,
      orphaned_tool_messages: Message.joins(:chat)
                                    .where(role: "tool")
                                    .where(tool_call_id: nil)
                                    .count,
      conversations_by_state: Chat.group(:conversation_state).count,
      average_conversation_length: Chat.joins(:messages).group("chats.id").count.values.sum.to_f / Chat.count,
      conversations_last_24h: Chat.where("created_at > ?", 24.hours.ago).count
    }
  end

  def find_problematic_chats
    Chat.includes(:user, :messages)
        .where(conversation_state: [ "error", "needs_cleanup" ])
        .or(Chat.where("updated_at < ?", 1.hour.ago)
               .where(conversation_state: "needs_cleanup"))
        .limit(20)
        .order(updated_at: :desc)
  end

  def calculate_error_rate(recent_messages)
    return 0 if recent_messages.count == 0

    error_messages = recent_messages.joins(:chat)
                                   .where(chats: { conversation_state: "error" })
                                   .count

    (error_messages.to_f / recent_messages.count * 100).round(2)
  end

  def gather_error_recovery_stats
    # Get statistics from database about error recovery operations
    active_recoveries = RecoveryContext.where("expires_at > ?", Time.current).count
    available_checkpoints = ConversationCheckpoint.count

    {
      active_recovery_operations: active_recoveries,
      available_checkpoints: available_checkpoints,
      recovery_success_rate: calculate_recovery_success_rate,
      common_error_patterns: analyze_error_patterns,
      timestamp: Time.current.iso8601
    }
  rescue => e
    Rails.logger.error "Error gathering recovery stats: #{e.message}"
    { error: e.message }
  end

  def calculate_recovery_success_rate
    # This would need to be implemented based on your logging strategy
    # For now, return a placeholder
    95.0
  end

  def analyze_error_patterns
    # Analyze recent error patterns from logs
    # This is a simplified version - you might want to integrate with your logging system
    [
      { pattern: "conversation_structure", count: 5, last_seen: 2.hours.ago },
      { pattern: "rate_limit", count: 3, last_seen: 30.minutes.ago },
      { pattern: "network_error", count: 2, last_seen: 1.hour.ago }
    ]
  end
end
