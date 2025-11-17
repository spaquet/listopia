# app/services/dashboard_adaptive_service.rb
class DashboardAdaptiveService
  attr_reader :user, :current_context

  def initialize(user, current_context = {})
    @user = user
    @current_context = current_context
  end

  # Main entry point - returns the entire dashboard state
  def call
    {
      mode: determine_mode,
      recommendations: generate_recommendations,
      spotlight: generate_spotlight,
      actions: generate_actions,
      context_data: current_context
    }
  end

  private

  # Get lists scoped to current organization
  def accessible_lists
    organization_id = current_context[:organization_id]
    if organization_id
      user.lists.where(organization_id: organization_id)
    else
      user.lists.where(organization_id: nil)
    end
  end

  # Determine which mode to show based on user state
  def determine_mode
    # Force a specific mode for testing if provided
    return current_context[:forced_mode] if current_context[:forced_mode].present?

    case user_state
    when :exploring
      :recommendations
    when :focused
      :spotlight
    when :ready_to_act
      :action
    when :idle
      :nudge
    else
      :recommendations
    end
  end

  # Analyze user's current state
  def user_state
    # If they have a selected list from previous interaction, go to spotlight
    if current_context[:selected_list_id].present?
      return :focused
    end

    # Check activity level - get max updated_at from user's accessible list items
    last_activity = ListItem.joins(:list)
                            .where(list: accessible_lists)
                            .maximum(:updated_at)
    days_since_activity = ((Time.current - last_activity) / 1.day).round if last_activity

    if days_since_activity && days_since_activity > 3
      return :idle
    end

    # Check if they're in the chat (we can pass this via context)
    if current_context[:in_chat].present?
      return :ready_to_act
    end

    # Default: exploring
    :exploring
  end

  # Generate ranked recommendations for exploration mode
  def generate_recommendations
    lists = accessible_lists.includes(:list_items, :collaborators)

    recommendations = lists.map do |list|
      score_list_for_recommendation(list)
    end.sort_by { |rec| rec[:score] }.reverse.first(5)

    recommendations
  end

  # Score a list for recommendation
  def score_list_for_recommendation(list)
    score = 0
    reason = []

    # Pending items weight (high priority)
    pending_count = list.list_items.status_pending.count
    score += pending_count * 10
    reason << "#{pending_count} pending" if pending_count > 0

    # Overdue items (very high priority)
    overdue_count = list.list_items
      .status_pending
      .where("due_date < ?", Time.current)
      .count
    score += overdue_count * 50
    reason << "#{overdue_count} overdue" if overdue_count > 0

    # Completion progress (motivational)
    total_items = list.list_items.count
    if total_items > 0
      completion_rate = list.list_items.status_completed.count.to_f / total_items
      # Close to completion = higher score
      if completion_rate > 0.7 && completion_rate < 1.0
        score += 30
        reason << "Almost done!"
      end
    end

    # Recent collaboration (needs your input)
    recent_collabs = list.list_items
      .where.not(assigned_user_id: nil)
      .where("updated_at > ?", 2.days.ago)
      .count
    score += recent_collabs * 15
    reason << "#{recent_collabs} collaborative items" if recent_collabs > 0

    # Freshness (recently worked on)
    days_since_update = ((Time.current - list.updated_at) / 1.day).round
    if days_since_update <= 1
      score += 20
      reason << "Updated today"
    elsif days_since_update <= 7
      score += 10
    end

    # List is stale (needs nudge back)
    if days_since_update > 7 && list.list_items.status_pending.count > 0
      score += 25
      reason << "Inactive for #{days_since_update} days"
    end

    {
      list_id: list.id,
      list_title: list.title,
      list_owner: list.owner.name,
      score: score,
      reason: reason.join(" • "),
      pending_count: pending_count,
      completion_rate: total_items > 0 ? (list.list_items.status_completed.count.to_f / total_items * 100).round : 0,
      next_item: next_pending_item(list),
      is_owned: list.user_id == user.id,
      collaborator_count: list.collaborators.count
    }
  end

  # Get next pending item for a list
  def next_pending_item(list)
    item = list.list_items
      .status_pending
      .order(:due_date, :created_at)
      .first

    return nil unless item

    {
      id: item.id,
      title: item.title,
      priority: item.priority,
      due_date: item.due_date,
      assigned_to: item.assigned_user&.name
    }
  end

  # Generate spotlight view for a specific list
  def generate_spotlight
    selected_list_id = current_context[:selected_list_id]

    # If no list selected but in spotlight mode, use first accessible list
    if selected_list_id.blank? && current_context[:forced_mode] == :spotlight
      first_list = accessible_lists.first
      selected_list_id = first_list&.id
    end

    return {} unless selected_list_id

    list = accessible_lists.find_by(id: selected_list_id)
    return {} unless list

    total_items = list.list_items.count
    completed_items = list.list_items.status_completed.count
    pending_items = list.list_items.status_pending.count
    overdue_items = list.list_items
      .status_pending
      .where("due_date < ?", Time.current)
      .count

    {
      list_id: list.id,
      list_title: list.title,
      list_description: list.description,
      progress: total_items > 0 ? (completed_items.to_f / total_items * 100).round : 0,
      stats: {
        total: total_items,
        completed: completed_items,
        pending: pending_items,
        overdue: overdue_items
      },
      next_items: list.list_items
        .status_pending
        .order(:due_date, :priority == "high" ? 0 : 1, :created_at)
        .limit(3)
        .map { |item| item_summary(item) },
      collaborators: list.collaborators.includes(:user).limit(5).map { |c| { id: c.user.id, name: c.user.name, avatar_url: c.user.avatar_url } },
      timeline: {
        created_at: list.created_at,
        updated_at: list.updated_at,
        first_item_completed_at: list.list_items.status_completed.minimum(:updated_at)
      }
    }
  end

  # Generate action panel
  def generate_actions
    {}  # Removed - not needed
  end

  # Helper to format item summary
  def item_summary(item)
    days_until_due = nil
    if item.due_date
      days_until_due = (item.due_date.to_date - Date.current).to_i
    end

    {
      id: item.id,
      title: item.title,
      priority: item.priority,
      due_date: item.due_date,
      assigned_to: item.assigned_user&.name,
      days_until_due: days_until_due
    }
  end
end
