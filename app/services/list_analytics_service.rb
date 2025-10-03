# app/services/list_analytics_service.rb
class ListAnalyticsService < ApplicationService
  # Service to provide analytics and insights for lists
  # Tracks usage patterns, completion rates, and collaboration metrics

  def initialize(list, user = nil)
    @list = list
    @user = user
  end

  def call
    {
      completion_stats: completion_statistics,
      activity_timeline: activity_timeline,
      collaboration_metrics: collaboration_metrics,
      productivity_insights: productivity_insights
    }
  end

  # Calculate completion statistics
  def completion_statistics
    items = @list.list_items
    total = items.count
    completed = items.completed.count

    {
      total_items: total,
      completed_items: completed,
      pending_items: total - completed,
      completion_rate: total > 0 ? (completed.to_f / total * 100).round(2) : 0,
      overdue_items: items.where("due_date < ? AND completed = false", Time.current).count
    }
  end

  # Generate activity timeline for the last 30 days
  def activity_timeline
    30.days.ago.to_date.upto(Date.current).map do |date|
      items_created = @list.list_items.where(created_at: date.all_day).count
      items_completed = @list.list_items.where(status_changed_at: date.all_day).count

      {
        date: date,
        items_created: items_created,
        items_completed: items_completed,
        activity_score: items_created + items_completed
      }
    end
  end

  # Calculate collaboration metrics
  def collaboration_metrics
    collaborations = @list.list_collaborations.includes(:user)

    {
      total_collaborators: collaborations.count,
      active_collaborators: count_active_collaborators,
      contribution_breakdown: collaborator_contributions,
      permission_distribution: {
        read_only: collaborations.permission_read.count,
        full_access: collaborations.permission_collaborate.count
      }
    }
  end

  # Generate productivity insights
  def productivity_insights
    insights = []

    # Check completion trends
    recent_completion_rate = recent_completion_rate()
    if recent_completion_rate > 80
      insights << { type: "positive", message: "Great job! High completion rate recently." }
    elsif recent_completion_rate < 30
      insights << { type: "warning", message: "Consider breaking down tasks or setting more achievable goals." }
    end

    # Check overdue items
    overdue_count = @list.list_items.where("due_date < ? AND completed = false", Time.current).count
    if overdue_count > 0
      insights << { type: "alert", message: "#{overdue_count} items are overdue." }
    end

    # Check collaboration activity
    if @list.list_collaborations.any? && count_active_collaborators == 0
      insights << { type: "info", message: "Consider reaching out to your collaborators for more engagement." }
    end

    insights
  end

  private

  # Count collaborators who have been active in the last 7 days
  def count_active_collaborators
    # This would require tracking user activity - simplified for now
    # In a real app, you'd track when users last accessed the list
    @list.list_collaborations.joins(:user).where(users: { updated_at: 7.days.ago.. }).count
  end

  # Calculate how much each collaborator has contributed
  def collaborator_contributions
    @list.list_items.joins(:assigned_user)
         .group("users.name")
         .group("list_items.status_completed")
         .count
         .transform_keys { |key| { user: key[0], completed: key[1] } }
  end

  # Calculate completion rate for the last 7 days
  def recent_completion_rate
    recent_items = @list.list_items.where(created_at: 7.days.ago..)
    return 0 if recent_items.empty?

    completed = recent_items.completed.count
    (completed.to_f / recent_items.count * 100).round(2)
  end
end
