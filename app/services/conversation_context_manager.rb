# app/services/conversation_context_manager.rb
class ConversationContextManager
  include ActiveModel::Model
  include ActiveModel::Attributes

  attr_accessor :user, :chat, :current_context

  def initialize(user:, chat: nil, current_context: {})
    @user = user
    @chat = chat
    @current_context = current_context
    @logger = Rails.logger
  end

  # Track user actions for future context resolution
  def track_action(action:, entity:, metadata: {})
    ConversationContext.track_action(
      user: @user,
      action: action,
      entity: entity,
      chat: @chat,
      metadata: metadata.merge(
        page: @current_context[:page],
        timestamp: Time.current.iso8601
      )
    )
  end

  # Resolve ambiguous references in user messages
  def resolve_references(message_content)
    references = extract_references(message_content)
    resolved_context = {}

    references.each do |ref_type, ref_value|
      case ref_type
      when :this_list, :current_list
        resolved_context[:list] = resolve_current_list
      when :these_items, :selected_items
        resolved_context[:items] = resolve_selected_items(ref_value)
      when :first_items, :last_items
        resolved_context[:items] = resolve_ordered_items(ref_value, message_content)
      when :recent_list, :last_list
        resolved_context[:list] = resolve_recent_list
      when :my_lists, :user_lists
        resolved_context[:lists] = resolve_user_lists
      when :completed_items, :pending_items
        resolved_context[:items] = resolve_items_by_status(ref_value)
      end
    end

    resolved_context
  end

  # Get context summary for AI instructions
  def build_context_summary
    recent_contexts = get_recent_contexts

    summary = {
      current_page: @current_context[:page],
      timestamp: Time.current.iso8601,
      recent_actions: summarize_recent_actions(recent_contexts),
      available_entities: get_available_entities,
      session_context: build_session_context
    }

    # Add specific context based on current page
    case @current_context[:page]
    when /lists#show/
      summary[:current_list] = get_current_list_context
    when /lists#index/
      summary[:user_lists] = get_user_lists_context
    when /dashboard#/
      summary[:dashboard] = get_dashboard_context
    end

    summary
  end

  # Enhanced context for AI tool selection
  def get_ai_context_instructions
    context_summary = build_context_summary
    recent_contexts = get_recent_contexts(limit: 10)

    instructions = []

    # Add current page context
    if context_summary[:current_list]
      list = context_summary[:current_list]
      instructions << "User is currently viewing '#{list[:title]}' (#{list[:status]}, #{list[:items_count]} items)."

      if list[:items_count] > 0
        instructions << "Available items: #{list[:recent_items].map { |item| "\"#{item[:title]}\"" }.join(', ')}."
      end
    end

    # Add recent interaction context
    if recent_contexts.any?
      recent_actions = recent_contexts.map(&:action).uniq
      instructions << "Recent actions: #{recent_actions.join(', ')}."
    end

    # Add disambiguation context
    disambiguation = build_disambiguation_context(recent_contexts)
    if disambiguation.any?
      instructions << "Context references: #{disambiguation.map { |k, v| "#{k}: #{v}" }.join(', ')}."
    end

    instructions.join(' ')
  end

  private

  def extract_references(message_content)
    message_lower = message_content.downcase
    references = {}

    # List references
    if message_lower.match?(/\b(this|current|the)\s+(list|todo|task\s*list)\b/)
      references[:this_list] = true
    end

    if message_lower.match?(/\b(my|user)\s+(lists?)\b/)
      references[:user_lists] = true
    end

    if message_lower.match?(/\b(recent|last|latest)\s+(list)\b/)
      references[:recent_list] = true
    end

    # Item references with quantity
    if (match = message_lower.match(/\b(first|top)\s+(\d+)\s+(items?|tasks?)\b/))
      references[:first_items] = { position: match[1], count: match[2].to_i }
    elsif message_lower.match?(/\b(first|top)\s+(item|task|few\s+items)\b/)
      references[:first_items] = { position: "first", count: 3 }
    end

    if (match = message_lower.match(/\b(last|bottom)\s+(\d+)\s+(items?|tasks?)\b/))
      references[:last_items] = { position: match[1], count: match[2].to_i }
    elsif message_lower.match?(/\b(last|bottom)\s+(item|task|few\s+items)\b/)
      references[:last_items] = { position: "last", count: 3 }
    end

    if (match = message_lower.match(/\b(\d+)(?:st|nd|rd|th)\s+(items?|tasks?)\b/))
      references[:ordered_items] = { position: match[1], count: match[2].to_i }
    end

    if message_lower.match?(/\b(these|selected|current)\s+(items?|tasks?)\b/)
      references[:selected_items] = true
    end

    if message_lower.match?(/\b(completed|done|finished)\s+(items?|tasks?)\b/)
      references[:completed_items] = "completed"
    end

    if message_lower.match?(/\b(pending|todo|incomplete|remaining)\s+(items?|tasks?)\b/)
      references[:pending_items] = "pending"
    end

    references
  end

  def resolve_current_list
    # Try current page context first
    if @current_context[:list_id]
      list = List.find_by(id: @current_context[:list_id])
      return format_list_context(list) if list&.readable_by?(@user)
    end

    # Fall back to most recent list interaction
    recent_list_context = @user.conversation_contexts
      .lists_recently_viewed
      .recent
      .first

    if recent_list_context
      list = recent_list_context.entity
      return format_list_context(list) if list&.readable_by?(@user)
    end

    # Fall back to user's most recent list
    list = @user.lists.recent.first
    format_list_context(list) if list
  end

  def resolve_selected_items(ref_value)
    # Check for selected items in session context
    if @current_context[:selected_items].present?
      return resolve_items_by_ids(@current_context[:selected_items])
    end

    # Fall back to recent item interactions
    recent_items = @user.conversation_contexts
      .items_recently_interacted
      .recent
      .limit(5)
      .map(&:entity)
      .compact
      .select { |item| item.list.readable_by?(@user) }

    recent_items.map { |item| format_item_context(item) }
  end

  def resolve_ordered_items(ref_value, message_content)
    current_list = resolve_current_list
    return [] unless current_list&.dig(:id)

    list = List.find_by(id: current_list[:id])
    return [] unless list&.readable_by?(@user)

    items = list.list_items.order(:position)

    if ref_value[:position] == "first"
      items = items.limit(ref_value[:count] || 3)
    elsif ref_value[:position] == "last"
      items = items.order(position: :desc).limit(ref_value[:count] || 3)
    end

    items.map { |item| format_item_context(item) }
  end

  def resolve_recent_list
    recent_context = @user.conversation_contexts
      .for_entity_type("List")
      .for_action(["list_created", "list_updated", "list_viewed"])
      .recent
      .first

    if recent_context
      list = recent_context.entity
      return format_list_context(list) if list&.readable_by?(@user)
    end

    # Fall back to most recently created/updated list
    list = @user.lists.order(updated_at: :desc).first
    format_list_context(list) if list
  end

  def resolve_items_by_status(status)
    current_list = resolve_current_list
    return [] unless current_list&.dig(:id)

    list = List.find_by(id: current_list[:id])
    return [] unless list&.readable_by?(@user)

    items = case status
    when "completed"
      list.list_items.completed
    when "pending"
      list.list_items.pending
    else
      list.list_items
    end

    items.limit(10).map { |item| format_item_context(item) }
  end

  def resolve_user_lists
    @user.lists.order(updated_at: :desc).limit(10).map { |list| format_list_context(list) }
  end

  def resolve_items_by_ids(item_ids)
    items = ListItem.where(id: item_ids)
                   .joins(:list)
                   .where(lists: { id: @user.accessible_lists.select(:id) })

    items.map { |item| format_item_context(item) }
  end

  def get_recent_contexts(limit: 20)
    @user.conversation_contexts
      .active
      .recent
      .limit(limit)
      .includes(:chat)
  end

  # FIXED: Use correct fields for ListItem
  def format_list_context(list)
    return nil unless list

    {
      id: list.id,
      title: list.title,
      status: list.status,
      items_count: list.list_items.count,
      completed_count: list.list_items.completed.count,
      is_owner: list.owner == @user,
      recent_items: list.list_items.order(updated_at: :desc).limit(5).map { |item|
        # Use completed boolean instead of status enum for ListItem
        {
          id: item.id,
          title: item.title,
          completed: item.completed,
          status: item.completed? ? "completed" : "pending"  # Create status for consistency
        }
      }
    }
  end

  # FIXED: Use correct fields for ListItem
  def format_item_context(item)
    return nil unless item

    {
      id: item.id,
      title: item.title,
      completed: item.completed,
      status: item.completed? ? "completed" : "pending",  # Create status for consistency
      list_id: item.list_id,
      list_title: item.list.title,
      position: item.position,
      priority: item.priority
    }
  end

  def summarize_recent_actions(contexts)
    contexts.group_by(&:action).transform_values(&:count)
  end

  def get_available_entities
    {
      accessible_lists: @user.accessible_lists.count,
      owned_lists: @user.lists.count,
      active_chats: @user.chats.status_active.count
    }
  end

  def build_session_context
    session_contexts = @user.conversation_contexts.current_session_contexts

    {
      actions_count: session_contexts.count,
      entities_interacted: session_contexts.distinct.count(:entity_id),
      started_at: session_contexts.minimum(:created_at)
    }
  end

  def get_current_list_context
    return nil unless @current_context[:list_id]

    list = List.find_by(id: @current_context[:list_id])
    format_list_context(list) if list&.readable_by?(@user)
  end

  def get_user_lists_context
    {
      total_lists: @user.accessible_lists.count,
      owned_lists: @user.lists.count,
      collaborated_lists: @user.collaborated_lists.count,
      recent_lists: @user.lists.order(updated_at: :desc).limit(5).map { |list|
        { id: list.id, title: list.title, status: list.status }
      }
    }
  end

  def get_dashboard_context
    {
      total_lists: @user.lists.count,
      active_lists: @user.lists.status_active.count,
      completed_lists: @user.lists.status_completed.count
    }
  end

  def build_disambiguation_context(contexts)
    disambiguation = {}

    # Most recent list context
    recent_list = contexts.find { |c| c.entity_type == "List" }
    if recent_list
      disambiguation["most recent list"] = recent_list.entity_data["title"]
    end

    # Most recent items
    recent_items = contexts.select { |c| c.entity_type == "ListItem" }.first(3)
    if recent_items.any?
      item_titles = recent_items.map { |c| c.entity_data["title"] }
      disambiguation["recent items"] = item_titles.join(', ')
    end

    disambiguation
  end

  # Class methods for cleanup
  class << self
    def cleanup_expired_contexts!
      cutoff_time = 7.days.ago
      expired_contexts = ConversationContext.where('created_at < ?', cutoff_time)

      cleanup_count = expired_contexts.count
      expired_contexts.delete_all

      Rails.logger.info "Cleaned up #{cleanup_count} expired conversation contexts"

      {
        total: cleanup_count,
        cutoff_time: cutoff_time
      }
    end
  end
end
