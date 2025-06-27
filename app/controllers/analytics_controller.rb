# app/controllers/analytics_controller.rb
class AnalyticsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_list
  before_action :authorize_analytics_access!

  # Main analytics dashboard for a list
  def index
    @analytics_data = build_analytics_data

    respond_to do |format|
      format.html
      format.json { render json: @analytics_data }
    end
  end

  private

  def set_list
    @list = current_user.accessible_lists.find(params[:list_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to lists_path, alert: "List not found."
  end

  def authorize_analytics_access!
    # Only collaborators with read access or higher can view analytics
    unless @list.readable_by?(current_user)
      redirect_to lists_path, alert: "You don't have permission to view analytics for this list."
    end
  end

  def build_analytics_data
    {
      # Overview metrics
      overview: overview_metrics,

      # Completion analysis
      completion: completion_analytics,

      # Productivity insights
      productivity: productivity_analytics,

      # Collaboration metrics
      collaboration: collaboration_analytics,

      # Time-based analysis
      timeline: timeline_analytics,

      # Item type distribution and category insights
      content: content_analytics,

      # Priority analysis
      priority: priority_analytics,

      # Category-specific insights
      categories: category_insights
    }
  end

  def overview_metrics
    items = @list.list_items

    {
      total_items: items.count,
      completed_items: items.completed.count,
      pending_items: items.pending.count,
      completion_rate: calculate_completion_rate(items),
      overdue_items: items.where("due_date < ? AND completed = false", Time.current).count,
      items_with_due_dates: items.where.not(due_date: nil).count,
      assigned_items: items.where.not(assigned_user_id: nil).count
    }
  end

  def completion_analytics
    items = @list.list_items
    completed_items = items.completed.where.not(completed_at: nil)

    # Calculate average completion time
    completion_times = completed_items.map do |item|
      next unless item.completed_at && item.created_at
      (item.completed_at - item.created_at) / 1.hour # in hours
    end.compact

    {
      avg_completion_time_hours: completion_times.any? ? completion_times.sum / completion_times.size : 0,
      fastest_completion_hours: completion_times.min || 0,
      slowest_completion_hours: completion_times.max || 0,
      completion_by_priority: completion_by_priority,
      completion_by_type: completion_by_item_type,
      recent_completion_trend: recent_completion_trend
    }
  end

  def productivity_analytics
    items = @list.list_items

    {
      most_productive_day: most_productive_day_of_week,
      items_created_last_30_days: items.where(created_at: 30.days.ago..).count,
      items_completed_last_30_days: items.completed.where(completed_at: 30.days.ago..).count,
      overdue_rate: calculate_overdue_rate,
      assignment_completion_rate: assignment_completion_rate,
      velocity_trend: velocity_trend # items completed per week over time
    }
  end

  def collaboration_analytics
    collaborations = @list.list_collaborations.includes(:user)

    {
      total_collaborators: collaborations.count,
      permission_breakdown: {
        read_only: collaborations.permission_read.count,
        full_access: collaborations.permission_collaborate.count
      },
      contributor_activity: contributor_activity,
      items_by_assignee: items_by_assignee,
      unassigned_items: @list.list_items.where(assigned_user_id: nil).count
    }
  end

  def timeline_analytics
    # Daily activity for the last 30 days
    30.days.ago.to_date.upto(Date.current).map do |date|
      items_created = @list.list_items.where(created_at: date.all_day).count
      items_completed = @list.list_items.where(completed_at: date.all_day).count

      {
        date: date,
        items_created: items_created,
        items_completed: items_completed,
        net_progress: items_completed - items_created
      }
    end
  end

  def content_analytics
    items = @list.list_items

    # Get counts for all item types, ensuring 0 for missing types
    type_counts = ListItem.item_types.keys.map do |type|
      [type, items.where(item_type: type).count]
    end.to_h

    {
      by_type: type_counts,
      # Group by categories for better visualization
      by_category: {
        planning: %w[task goal milestone action_item waiting_for reminder].sum { |type| type_counts[type] || 0 },
        knowledge: %w[idea note reference].sum { |type| type_counts[type] || 0 },
        personal: %w[habit health learning travel shopping home finance social entertainment].sum { |type| type_counts[type] || 0 }
      },
      avg_title_length: items.any? ? items.average("LENGTH(title)").to_f.round(1) : 0,
      items_with_descriptions: items.where.not(description: [nil, ""]).count,
      items_with_urls: items.where.not(url: [nil, ""]).count,
      items_with_reminders: items.where.not(reminder_at: nil).count,
      items_with_due_dates: items.where.not(due_date: nil).count
    }
  end

  def priority_analytics
    items = @list.list_items

    # Ensure all priorities have default values
    priority_distribution = ListItem.priorities.keys.map do |priority|
      [priority, items.where(priority: priority).count]
    end.to_h

    priority_completion = ListItem.priorities.keys.map do |priority|
      priority_items = items.where(priority: priority)
      [priority, calculate_completion_rate(priority_items)]
    end.to_h

    {
      distribution: priority_distribution,
      completion_by_priority: priority_completion,
      overdue_by_priority: overdue_by_priority
    }
  end

  # Helper methods

  def calculate_completion_rate(items)
    return 0 if items.count.zero?
    (items.completed.count.to_f / items.count * 100).round(2)
  end

  def completion_by_priority
    ListItem.priorities.keys.map do |priority|
      items = @list.list_items.where(priority: priority)
      [priority, calculate_completion_rate(items)]
    end.to_h
  end

  def completion_by_item_type
    ListItem.item_types.keys.map do |type|
      items = @list.list_items.where(item_type: type)
      [type, calculate_completion_rate(items)]
    end.to_h
  end

  def most_productive_day_of_week
    completed_by_day = @list.list_items.completed
                           .where.not(completed_at: nil)
                           .group("EXTRACT(DOW FROM completed_at)")
                           .count

    day_names = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday]
    return "No data" if completed_by_day.empty?

    most_productive_day_num = completed_by_day.max_by { |_, count| count }&.first
    day_names[most_productive_day_num.to_i] if most_productive_day_num
  end

  def calculate_overdue_rate
    items_with_due_dates = @list.list_items.where.not(due_date: nil)
    return 0 if items_with_due_dates.count.zero?

    overdue_count = items_with_due_dates.where("due_date < ? AND completed = false", Time.current).count
    (overdue_count.to_f / items_with_due_dates.count * 100).round(2)
  end

  def assignment_completion_rate
    assigned_items = @list.list_items.where.not(assigned_user_id: nil)
    calculate_completion_rate(assigned_items)
  end

  def contributor_activity
    @list.list_items.joins(:assigned_user)
         .group("users.name")
         .group("list_items.completed")
         .count
         .each_with_object({}) do |((name, completed), count), hash|
           hash[name] ||= { completed: 0, pending: 0 }
           hash[name][completed ? :completed : :pending] = count
         end
  end

  def items_by_assignee
    @list.list_items.joins(:assigned_user)
         .group("users.name")
         .count
  end

  def recent_completion_trend
    # Last 7 days completion trend
    7.days.ago.to_date.upto(Date.current).map do |date|
      completed = @list.list_items.where(completed_at: date.all_day).count
      [date.strftime("%a"), completed]
    end.to_h
  end

  def velocity_trend
    # Weekly velocity for the last 8 weeks
    8.times.map do |weeks_ago|
      week_start = weeks_ago.weeks.ago.beginning_of_week
      week_end = weeks_ago.weeks.ago.end_of_week
      completed = @list.list_items.where(completed_at: week_start..week_end).count

      {
        week: "#{week_start.strftime('%m/%d')} - #{week_end.strftime('%m/%d')}",
        completed: completed
      }
    end.reverse
  end

  def overdue_by_priority
    ListItem.priorities.keys.map do |priority|
      overdue = @list.list_items.where(priority: priority)
                     .where("due_date < ? AND completed = false", Time.current)
                     .count
      [priority, overdue]
    end.to_h
  end

  def category_insights
    items = @list.list_items

    # Define category groupings
    categories = {
      planning: %w[task goal milestone action_item waiting_for reminder],
      knowledge: %w[idea note reference],
      personal: %w[habit health learning travel shopping home finance social entertainment]
    }

    insights = {}

    categories.each do |category, types|
      category_items = items.where(item_type: types)

      insights[category] = {
        total_items: category_items.count,
        completed_items: category_items.completed.count,
        completion_rate: calculate_completion_rate(category_items),
        most_common_type: most_common_type_in_category(category_items),
        avg_completion_time: avg_completion_time_for_items(category_items)
      }
    end

    insights
  end

  def most_common_type_in_category(items)
    return nil if items.empty?

    type_counts = items.group(:item_type).count
    most_common = type_counts.max_by { |_, count| count }
    most_common&.first
  end

  def avg_completion_time_for_items(items)
    completed_items = items.completed.where.not(completed_at: nil)

    completion_times = completed_items.map do |item|
      next unless item.completed_at && item.created_at
      (item.completed_at - item.created_at) / 1.hour
    end.compact

    completion_times.any? ? (completion_times.sum / completion_times.size).round(2) : 0
  end
end
