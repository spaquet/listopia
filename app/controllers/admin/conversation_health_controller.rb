# app/controllers/admin/conversation_health_controller.rb
class Admin::ConversationHealthController < ApplicationController
  def index
    @health_stats = calculate_health_stats
    @recent_issues = recent_conversation_issues
    @trending_problems = trending_problem_patterns
  end

  def check_all
    ConversationHealthCheckJob.perform_later
    redirect_to admin_conversation_health_index_path, notice: "Health check started in background"
  end

  def repair_chat
    chat = Chat.find(params[:chat_id])

    begin
      chat.repair_conversation!
      flash[:notice] = "Successfully repaired chat #{chat.id}"
    rescue => e
      flash[:alert] = "Failed to repair chat: #{e.message}"
    end

    redirect_to admin_conversation_health_index_path
  end

  def show_chat_details
    @chat = Chat.find(params[:id])
    @conversation_manager = ConversationStateManager.new(@chat)

    begin
      @conversation_manager.ensure_conversation_integrity!
      @chat_status = "healthy"
    rescue ConversationStateManager::ConversationError => e
      @chat_status = "unhealthy"
      @error_details = e.message
    end

    @chat_stats = @chat.conversation_stats
  end

  private

  def calculate_health_stats
    total_chats = Chat.status_active.count
    return { total_chats: 0, healthy_percentage: 100 } if total_chats.zero?

    healthy_count = 0
    Chat.status_active.includes(:messages, :tool_calls).find_each do |chat|
      begin
        ConversationStateManager.new(chat).ensure_conversation_integrity!
        healthy_count += 1
      rescue ConversationStateManager::ConversationError
        # Chat has issues
      end
    end

    {
      total_chats: total_chats,
      healthy_chats: healthy_count,
      unhealthy_chats: total_chats - healthy_count,
      healthy_percentage: (healthy_count.to_f / total_chats * 100).round(2),
      orphaned_tool_messages: Message.where(role: "tool", tool_call_id: [ nil, "" ]).count,
      last_health_check: Rails.cache.read("last_conversation_health_check")
    }
  end

  def recent_conversation_issues
    # Get chats that were recently archived due to conversation issues
    Chat.where(status: "archived")
        .where("metadata->>'archived_reason' = ?", "conversation_integrity_failure")
        .where("updated_at > ?", 24.hours.ago)
        .order(updated_at: :desc)
        .limit(10)
        .includes(:user)
  end

  def trending_problem_patterns
    # Analyze patterns in conversation issues
    archived_chats = Chat.where(status: "archived")
                        .where("metadata->>'archived_reason' = ?", "conversation_integrity_failure")
                        .where("updated_at > ?", 7.days.ago)

    patterns = archived_chats.group("metadata->>'original_error'").count

    patterns.map do |error_type, count|
      {
        error_type: error_type,
        count: count,
        percentage: (count.to_f / archived_chats.count * 100).round(2)
      }
    end.sort_by { |p| -p[:count] }
  end
end
